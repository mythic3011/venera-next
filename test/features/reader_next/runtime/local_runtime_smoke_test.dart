import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/features/reader_next/infrastructure/local_runtime_session_writer.dart';
import 'package:venera/features/reader_next/runtime/local_runtime_smoke.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/adapters/unified_comic_detail_store_adapter.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local.dart';

void main() {
  late Directory tempDir;
  late Directory localRoot;
  late UnifiedComicsStore store;
  late UnifiedComicDetailStoreAdapter storeAdapter;
  late ReaderSessionRepository sessionRepository;
  late LocalReaderRuntimeSmokeService service;
  late List<Uint8List> decodedImages;

  Future<void> syncComic(LocalComic comic) {
    return LocalComicCanonicalSyncService(
      store: store,
      resolveCanonicalLocalRootPath: () async => localRoot.path,
    ).syncComic(comic);
  }

  LocalComic buildFlatComic({
    required String comicId,
    required String title,
    required Directory directory,
  }) {
    return LocalComic(
      id: comicId,
      title: title,
      subtitle: '',
      tags: const <String>[],
      directory: directory.path,
      chapters: null,
      cover: 'cover.png',
      comicType: ComicType.local,
      downloadedChapters: const <String>[],
      createdAt: DateTime.utc(2026, 5, 5),
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'reader-next-local-runtime-smoke-',
    );
    localRoot = Directory(p.join(tempDir.path, 'runtimeRoot', 'local'))
      ..createSync(recursive: true);
    store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    await store.seedDefaultSourcePlatforms();
    storeAdapter = UnifiedComicDetailStoreAdapter(store);
    sessionRepository = ReaderSessionRepository(store: storeAdapter);
    decodedImages = <Uint8List>[];
    AppDiagnostics.configureSinksForTesting(const []);
    service = LocalReaderRuntimeSmokeService(
      store: storeAdapter,
      sessionWriter: CanonicalLocalReaderSessionWriter(
        repository: sessionRepository,
      ),
      decodeFirstPage: (bytes) async {
        decodedImages.add(bytes);
      },
    );
  });

  tearDown(() async {
    AppDiagnostics.resetForTesting();
    await store.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'flat local comic with pages and no chapters resolves imported runtime target and persists session',
    () async {
      final comicDir = Directory(p.join(tempDir.path, 'Flat Comic'))
        ..createSync(recursive: true);
      File(p.join(comicDir.path, 'cover.png')).writeAsBytesSync(<int>[9]);
      File(p.join(comicDir.path, '1.png')).writeAsBytesSync(<int>[1, 2, 3]);
      File(p.join(comicDir.path, '2.png')).writeAsBytesSync(<int>[4, 5, 6]);
      await syncComic(
        buildFlatComic(
          comicId: 'flat-1',
          title: 'Flat Comic',
          directory: comicDir,
        ),
      );

      final result = await service.open(
        const LocalReaderRuntimeInput(
          comicId: 'flat-1',
          sourceKey: 'local',
          loadMode: 'local',
        ),
      );

      expect(result, isA<LocalReaderRuntimeOpenSuccess>());
      final success = result as LocalReaderRuntimeOpenSuccess;
      expect(success.target.chapterId, 'flat-1:__imported__');
      expect(
        success.target.sourceRefId,
        'local:local:flat-1:flat-1:__imported__',
      );
      expect(success.target.sourceRefId.endsWith(':_'), isFalse);
      expect(success.pageList, hasLength(3));
      expect(success.firstPage.imageKey, 'local:flat-1:__imported__:0');
      expect(success.firstPage.imageUrl, startsWith('file://'));
      expect(success.firstPageBytes, <int>[1, 2, 3]);
      expect(decodedImages.single, Uint8List.fromList(<int>[1, 2, 3]));
      expect(success.sessionPersist.written, isTrue);
      expect(success.sessionPersist.skipReason, isNull);

      final runtimeEvent = DevDiagnosticsApi.recent(
        channel: 'reader.local',
      ).singleWhere((event) => event.message == 'reader.local.runtime.success');
      expect(runtimeEvent.data['comicId'], 'flat-1');
      expect(runtimeEvent.data['chapterId'], 'flat-1:__imported__');
      expect(
        runtimeEvent.data['sourceRefId'],
        'local:local:flat-1:flat-1:__imported__',
      );
      expect(
        DevDiagnosticsApi.recent(
          channel: 'reader.decode',
        ).map((event) => event.message),
        contains('image.decode.success'),
      );
    },
  );

  test('persist reports skipped on unchanged local runtime reopen', () async {
    final comicDir = Directory(p.join(tempDir.path, 'Flat Comic Reopen'))
      ..createSync(recursive: true);
    File(p.join(comicDir.path, 'cover.png')).writeAsBytesSync(<int>[7]);
    File(p.join(comicDir.path, '1.png')).writeAsBytesSync(<int>[8, 9, 10]);
    await syncComic(
      buildFlatComic(
        comicId: 'flat-2',
        title: 'Flat Comic Reopen',
        directory: comicDir,
      ),
    );

    final first = await service.open(
      const LocalReaderRuntimeInput(
        comicId: 'flat-2',
        sourceKey: 'local',
        loadMode: 'local',
      ),
    );
    final second = await service.open(
      const LocalReaderRuntimeInput(
        comicId: 'flat-2',
        sourceKey: 'local',
        loadMode: 'local',
      ),
    );

    expect(
      (first as LocalReaderRuntimeOpenSuccess).sessionPersist.written,
      isTrue,
    );
    expect(
      (second as LocalReaderRuntimeOpenSuccess).sessionPersist.written,
      isFalse,
    );
    expect(
      (second).sessionPersist.skipReason,
      anyOf('unchanged', 'unchanged_memory'),
    );
  });

  test(
    'missing pages returns typed failure and emits reader.local.default_chapter.missing_pages',
    () async {
      final comicDir = Directory(p.join(tempDir.path, 'Flat Comic Empty'))
        ..createSync(recursive: true);
      await syncComic(
        buildFlatComic(
          comicId: 'flat-empty',
          title: 'Flat Comic Empty',
          directory: comicDir,
        ),
      );

      final result = await service.open(
        const LocalReaderRuntimeInput(
          comicId: 'flat-empty',
          sourceKey: 'local',
          loadMode: 'local',
        ),
      );

      expect(result, isA<LocalReaderRuntimeOpenFailure>());
      final failure = result as LocalReaderRuntimeOpenFailure;
      expect(
        failure.error.code,
        LocalReaderRuntimeFailureCode.defaultChapterMissingPages,
      );
      expect(
        failure.error.diagnostic,
        'reader.local.default_chapter.missing_pages',
      );
      expect(
        failure.target?.sourceRefId,
        'local:local:flat-empty:flat-empty:__imported__',
      );
      expect(failure.target?.sourceRefId.endsWith(':_'), isFalse);
      expect(decodedImages, isEmpty);
      expect(
        DevDiagnosticsApi.recent(
          channel: 'reader.local',
        ).map((event) => event.message),
        contains('reader.local.default_chapter.missing_pages'),
      );
    },
  );

  test(
    'runtime local open pipeline does not reference legacy appdata resume',
    () async {
      final content = await File(
        p.join(
          Directory.current.path,
          'lib/features/reader_next/runtime/local_runtime_smoke.dart',
        ),
      ).readAsString();

      expect(content.contains('HistoryManager'), isFalse);
      expect(content.contains('ResumeTargetStore'), isFalse);
      expect(content.contains('reading_resume_targets_v1'), isFalse);
      expect(content.contains('implicitData'), isFalse);
      expect(content.contains('ReaderWithLoading'), isFalse);
    },
  );
}
