import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/reader_activity_repository.dart';
import 'package:venera/foundation/reader/reader_resume_service.dart';
import 'package:venera/foundation/reader/reader_runtime_context.dart';
import 'package:venera/foundation/reader/reader_session_persistence.dart';
import 'package:venera/foundation/reader/reader_session_repository.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
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
    ).loadPreferredResumeSourceRef('legacy', ComicType.local);

    expect(preferred, isNull);
    expect(legacyJson.existsSync(), isTrue);
  });
}
