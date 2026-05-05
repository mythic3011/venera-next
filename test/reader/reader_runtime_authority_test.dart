import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/features/reader/data/reader_activity_repository.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/features/reader/data/reader_resume_service.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/features/reader/data/reader_session_persistence.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/features/reader/presentation/reader.dart';

void main() {
  test('live reader runtime does not read legacy resume state directly', () async {
    final repoRoot = Directory.current.path;
    final liveRuntimeFiles = <String>{
      'lib/features/reader/data/reader_resume_service.dart',
      'lib/features/reader/presentation/loading.dart',
      'lib/features/reader/presentation/reader_route_dispatch_authority.dart',
      'lib/pages/comic_details_page/actions.dart',
      'lib/foundation/local/local_comic.dart',
    };
    for (final relativePath in liveRuntimeFiles) {
      final content = await File('$repoRoot/$relativePath').readAsString();
      expect(
        content.contains('findResumeSourceRef('),
        isFalse,
        reason: '$relativePath must not read legacy resume state directly',
      );
      expect(
        content.contains('reading_resume_targets_v1'),
        isFalse,
        reason: '$relativePath must not depend on legacy resume appdata state',
      );
      expect(
        content.contains('implicitData'),
        isFalse,
        reason: '$relativePath must not bind live reader routing to appdata',
      );
    }

    final migrationAdapter = await File(
      '$repoRoot/lib/features/reader/data/reader_legacy_resume_migration_adapter.dart',
    ).readAsString();
    expect(migrationAdapter.contains('readResumeSnapshotWithDiagnostic'), isTrue);
    expect(migrationAdapter.contains('reading_resume_targets_v1'), isTrue);
  });

  test(
    'canonical session persistence does not create legacy runtime stores',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reader-authority-',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = UnifiedComicsStore(
        p.join(tempDir.path, 'data', 'venera.db'),
      );
      await store.init();
      addTearDown(store.close);
      await store.upsertComic(
        const ComicRecord(
          id: 'local-1',
          title: 'Local 1',
          normalizedTitle: 'local 1',
        ),
      );

      final repository = ReaderSessionRepository(store: store);
      final context = buildReaderRuntimeContextForTesting(
        comicId: 'local-1',
        type: ComicType.local,
        chapterIndex: 1,
        page: 1,
        chapterId: null,
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'local-1',
          chapterId: null,
        ),
      );

      await persistReaderSessionContextForTesting(
        repository: repository,
        context: context,
      );
      final activityRepository = ReaderActivityRepository(store: store);
      final activity = await activityRepository.loadRecent();

      expect(
        File(p.join(tempDir.path, 'data', 'venera.db')).existsSync(),
        isTrue,
      );
      expect(activity.map((item) => item.comicId), ['local-1']);
      expect(File(p.join(tempDir.path, 'history.db')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'local.db')).existsSync(), isFalse);
      expect(
        File(p.join(tempDir.path, 'local_favorite.db')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(tempDir.path, 'implicitData.json')).existsSync(),
        isFalse,
      );
    },
  );

  test('canonical resume lookup ignores legacy json-only state', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'reader-authority-resume-',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final legacyJson = File(p.join(tempDir.path, 'implicitData.json'));
    await legacyJson.writeAsString(
      '{"resumeTargets":{"local@@legacy":{"sourceRef":{"type":"local"}}}}',
    );

    final store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    addTearDown(store.close);

    final preferred = await ReaderResumeService(
      readerSessions: ReaderSessionRepository(store: store),
    ).loadPreferredResumeTarget('legacy', ComicType.local);

    expect(preferred, isNull);
    expect(legacyJson.existsSync(), isTrue);
  });

  test(
    'canonical compatibility history reads resume state without creating legacy stores',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reader-authority-history-',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = UnifiedComicsStore(
        p.join(tempDir.path, 'data', 'venera.db'),
      );
      await store.init();
      addTearDown(store.close);
      await store.upsertComic(
        const ComicRecord(
          id: 'local-2',
          title: 'Local 2',
          normalizedTitle: 'local 2',
        ),
      );

      final repository = ReaderSessionRepository(store: store);
      await persistReaderSessionContextForTesting(
        repository: repository,
        context: buildReaderRuntimeContextForTesting(
          comicId: 'local-2',
          type: ComicType.local,
          chapterIndex: 2,
          page: 6,
          chapterId: 'chapter-2',
          sourceRef: SourceRef.fromLegacyLocal(
            localType: 'local',
            localComicId: 'local-2',
            chapterId: 'chapter-2',
          ),
        ),
      );

      final tab = await repository.loadActiveReaderTab('local-2');
      final history = buildReaderCompatibilityHistory(
        model: _RuntimeHistoryModel(
          title: 'Local 2',
          subTitle: '',
          cover: '',
          id: 'local-2',
          historyType: ComicType.local,
        ),
        chapters: const ComicChapters({
          'chapter-1': 'Episode 1',
          'chapter-2': 'Episode 2',
        }),
        canonicalActiveTab: tab,
      );

      expect(history.ep, 2);
      expect(history.page, 6);
      expect(File(p.join(tempDir.path, 'history.db')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'local.db')).existsSync(), isFalse);
      expect(
        File(p.join(tempDir.path, 'local_favorite.db')).existsSync(),
        isFalse,
      );
    },
  );
}

class _RuntimeHistoryModel with HistoryMixin {
  _RuntimeHistoryModel({
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.id,
    required this.historyType,
  });

  @override
  final String title;

  @override
  final String? subTitle;

  @override
  final String cover;

  @override
  final String id;

  @override
  final ComicType historyType;
}
