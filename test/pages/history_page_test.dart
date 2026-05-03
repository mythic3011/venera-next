import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/db/adapters/unified_comic_detail_store_adapter.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/features/reader/data/reader_activity_repository.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/pages/history_page.dart';

void main() {
  Future<UnifiedComicsStore> createStore(Directory tempDir) async {
    final store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-a',
        title: 'Comic A',
        normalizedTitle: 'comic a',
      ),
    );
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-b',
        title: 'Comic B',
        normalizedTitle: 'comic b',
      ),
    );
    return store;
  }

  void expectNoLegacyRuntimeFiles(Directory tempDir) {
    expect(File(p.join(tempDir.path, 'history.db')).existsSync(), isFalse);
    expect(
      File(p.join(tempDir.path, 'implicitData.json')).existsSync(),
      isFalse,
    );
  }

  test(
    'history page helpers read canonical activity without legacy init',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('history-page-');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final store = await createStore(tempDir);
      addTearDown(store.close);
      final sessions = ReaderSessionRepository(store: store);
      final repository = ReaderActivityRepository(store: store);

      await sessions.upsertCurrentLocation(
        comicId: 'comic-a',
        chapterId: 'chapter-a',
        pageIndex: 2,
        sourceRef: SourceRef.fromLegacy(
          comicId: 'comic-a',
          sourceKey: 'remote-history-source',
        ),
      );
      await sessions.upsertCurrentLocation(
        comicId: 'comic-b',
        chapterId: 'chapter-b',
        pageIndex: 4,
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-b',
          chapterId: 'chapter-b',
        ),
      );

      final items = await loadHistoryPageActivity(repository);

      expect(items, hasLength(2));
      expect(items.map((item) => item.comicId).toSet(), {'comic-a', 'comic-b'});
      expectNoLegacyRuntimeFiles(tempDir);
    },
  );

  test('history page remove action deletes canonical activity only', () async {
    final tempDir = await Directory.systemTemp.createTemp('history-remove-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final store = await createStore(tempDir);
    addTearDown(store.close);
    final sessions = ReaderSessionRepository(store: store);
    final repository = ReaderActivityRepository(store: store);

    await sessions.upsertCurrentLocation(
      comicId: 'comic-a',
      chapterId: 'chapter-a',
      pageIndex: 2,
      sourceRef: SourceRef.fromLegacy(
        comicId: 'comic-a',
        sourceKey: 'remote-history-source',
      ),
    );
    await sessions.upsertCurrentLocation(
      comicId: 'comic-b',
      chapterId: 'chapter-b',
      pageIndex: 4,
      sourceRef: SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-b',
        chapterId: 'chapter-b',
      ),
    );

    await removeHistoryPageActivity(repository, 'comic-a');

    final items = await loadHistoryPageActivity(repository);
    expect(items.map((item) => item.comicId), ['comic-b']);
    expectNoLegacyRuntimeFiles(tempDir);
  });

  test('history page clear action deletes canonical activity only', () async {
    final tempDir = await Directory.systemTemp.createTemp('history-clear-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final store = await createStore(tempDir);
    addTearDown(store.close);
    final sessions = ReaderSessionRepository(store: store);
    final repository = ReaderActivityRepository(store: store);

    await sessions.upsertCurrentLocation(
      comicId: 'comic-a',
      chapterId: 'chapter-a',
      pageIndex: 2,
      sourceRef: SourceRef.fromLegacy(
        comicId: 'comic-a',
        sourceKey: 'remote-history-source',
      ),
    );
    await sessions.upsertCurrentLocation(
      comicId: 'comic-b',
      chapterId: 'chapter-b',
      pageIndex: 4,
      sourceRef: SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-b',
        chapterId: 'chapter-b',
      ),
    );

    await clearHistoryPageActivity(repository);

    expect(await loadHistoryPageActivity(repository), isEmpty);
    expectNoLegacyRuntimeFiles(tempDir);
  });

  test('reader activity repository canonicalizes local cover path', () async {
    final tempDir = await Directory.systemTemp.createTemp('history-cover-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final store = await createStore(tempDir);
    addTearDown(store.close);
    final coverFile = File(p.join(tempDir.path, 'cover-b.png'));
    coverFile.writeAsBytesSync(const [1, 2, 3]);
    await store.upsertComic(
      ComicRecord(
        id: 'comic-local-cover',
        title: 'Comic Local Cover',
        normalizedTitle: 'comic local cover',
        coverLocalPath: coverFile.path,
      ),
    );
    final sessions = ReaderSessionRepository(store: store);
    await sessions.upsertCurrentLocation(
      comicId: 'comic-local-cover',
      chapterId: '1:__imported__',
      pageIndex: 3,
      sourceRef: SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-local-cover',
        chapterId: '1:__imported__',
      ),
    );
    final repository = ReaderActivityRepository(
      store: store,
      comicDetailStore: UnifiedComicDetailStoreAdapter(store),
    );

    final items = await loadHistoryPageActivity(repository);

    expect(items, hasLength(1));
    expect(items.single.cover, Uri.file(coverFile.path).toString());
  });
}
