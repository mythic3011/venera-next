import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/reader_activity_repository.dart';
import 'package:venera/foundation/reader/reader_session_repository.dart';
import 'package:venera/foundation/source_ref.dart';

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
    expect(File(p.join(tempDir.path, 'local.db')).existsSync(), isFalse);
    expect(File(p.join(tempDir.path, 'local_favorite.db')).existsSync(), isFalse);
    expect(File(p.join(tempDir.path, 'implicitData.json')).existsSync(), isFalse);
  }

  test('loadRecent returns canonical activity ordered by latest update', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'reader-activity-recent-',
    );
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
      pageIndex: 3,
      sourceRef: SourceRef.fromLegacy(
        comicId: 'comic-a',
        sourceKey: 'remote-source-a',
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    await sessions.upsertCurrentLocation(
      comicId: 'comic-b',
      chapterId: 'chapter-b',
      pageIndex: 7,
      sourceRef: SourceRef.fromLegacyLocal(
        localType: ComicType.local.sourceKey,
        localComicId: 'comic-b',
        chapterId: 'chapter-b',
      ),
    );

    final items = await repository.loadRecent(limit: 20);

    expect(items.map((item) => item.comicId), ['comic-b', 'comic-a']);
    expect(items.first.sourceKey, ComicType.local.sourceKey);
    expect(items.first.chapterId, 'chapter-b');
    expect(items.first.pageIndex, 7);
    expectNoLegacyRuntimeFiles(tempDir);
  });

  test('loadAll and count read canonical activity rows only', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'reader-activity-all-',
    );
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
      pageIndex: 3,
      sourceRef: SourceRef.fromLegacy(
        comicId: 'comic-a',
        sourceKey: 'remote-source-a',
      ),
    );
    await sessions.upsertCurrentLocation(
      comicId: 'comic-b',
      chapterId: 'chapter-b',
      pageIndex: 7,
      sourceRef: SourceRef.fromLegacyLocal(
        localType: ComicType.local.sourceKey,
        localComicId: 'comic-b',
        chapterId: 'chapter-b',
      ),
    );

    final items = await repository.loadAll();
    final count = await repository.count();

    expect(items, hasLength(2));
    expect(count, 2);
    expect(items.map((item) => item.comicId).toSet(), {'comic-a', 'comic-b'});
    expectNoLegacyRuntimeFiles(tempDir);
  });

  test('remove deletes one canonical reader session by comic id', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'reader-activity-remove-',
    );
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
      pageIndex: 3,
      sourceRef: SourceRef.fromLegacy(
        comicId: 'comic-a',
        sourceKey: 'remote-source-a',
      ),
    );
    await sessions.upsertCurrentLocation(
      comicId: 'comic-b',
      chapterId: 'chapter-b',
      pageIndex: 7,
      sourceRef: SourceRef.fromLegacyLocal(
        localType: ComicType.local.sourceKey,
        localComicId: 'comic-b',
        chapterId: 'chapter-b',
      ),
    );

    await repository.remove('comic-a');

    expect((await repository.loadAll()).map((item) => item.comicId), ['comic-b']);
    expect(await repository.count(), 1);
    expectNoLegacyRuntimeFiles(tempDir);
  });

  test('clear deletes all canonical reader sessions', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'reader-activity-clear-',
    );
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
      pageIndex: 3,
      sourceRef: SourceRef.fromLegacy(
        comicId: 'comic-a',
        sourceKey: 'remote-source-a',
      ),
    );
    await sessions.upsertCurrentLocation(
      comicId: 'comic-b',
      chapterId: 'chapter-b',
      pageIndex: 7,
      sourceRef: SourceRef.fromLegacyLocal(
        localType: ComicType.local.sourceKey,
        localComicId: 'comic-b',
        chapterId: 'chapter-b',
      ),
    );

    await repository.clear();

    expect(await repository.loadAll(), isEmpty);
    expect(await repository.count(), 0);
    expectNoLegacyRuntimeFiles(tempDir);
  });
}
