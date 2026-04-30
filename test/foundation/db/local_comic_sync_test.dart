import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/comic_type.dart';

void main() {
  late Directory tempDir;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('venera-local-sync-test-');
    store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    await store.seedDefaultSourcePlatforms();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('syncs flat local comic into canonical tables with default chapter', () async {
    final comicDir = Directory(p.join(tempDir.path, 'Flat Comic'))
      ..createSync(recursive: true);
    File(p.join(comicDir.path, 'cover.png')).writeAsBytesSync([1, 2, 3]);
    File(p.join(comicDir.path, '1.png')).writeAsBytesSync([1]);
    File(p.join(comicDir.path, '2.png')).writeAsBytesSync([1, 2]);

    final comic = LocalComic(
      id: 'flat-1',
      title: 'Flat Comic',
      subtitle: 'Local subtitle',
      tags: const ['artist:test'],
      directory: comicDir.path,
      chapters: null,
      cover: 'cover.png',
      comicType: ComicType.local,
      downloadedChapters: const [],
      createdAt: DateTime.utc(2026, 4, 30),
    );

    await LocalComicCanonicalSyncService(store: store).syncComic(comic);

    final snapshot = await store.loadComicSnapshot('flat-1');
    final summary = await store.loadPageOrderSummary('flat-1');

    expect(snapshot, isNotNull);
    expect(snapshot!.comic.title, 'Flat Comic');
    expect(snapshot.localLibraryItems.single.localRootPath, comicDir.path);
    expect(snapshot.chapters, hasLength(1));
    expect(snapshot.chapters.single.id, 'flat-1:__imported__');
    expect(summary.totalPageCount, 3);
    expect(summary.activeOrderType, 'source_default');
  });

  test('syncs chaptered local comic with chapter ids and page counts', () async {
    final comicDir = Directory(p.join(tempDir.path, 'Chaptered Comic'))
      ..createSync(recursive: true);
    File(p.join(comicDir.path, 'cover.png')).writeAsBytesSync([9]);
    final chapterOneDir = Directory(
      p.join(comicDir.path, LocalManager.getChapterDirectoryName('Chapter/1')),
    )..createSync(recursive: true);
    final chapterTwoDir = Directory(
      p.join(comicDir.path, LocalManager.getChapterDirectoryName('Chapter:2')),
    )..createSync(recursive: true);
    File(p.join(chapterOneDir.path, '2.png')).writeAsBytesSync([2]);
    File(p.join(chapterOneDir.path, '1.png')).writeAsBytesSync([1]);
    File(p.join(chapterTwoDir.path, '1.png')).writeAsBytesSync([3]);

    final comic = LocalComic(
      id: 'chap-1',
      title: 'Chaptered Comic',
      subtitle: '',
      tags: const [],
      directory: comicDir.path,
      chapters: ComicChapters({
        'Chapter/1': 'Opening',
        'Chapter:2': 'Ending',
      }),
      cover: 'cover.png',
      comicType: ComicType.local,
      downloadedChapters: const ['Chapter/1', 'Chapter:2'],
      createdAt: DateTime.utc(2026, 4, 30, 12),
    );

    await LocalComicCanonicalSyncService(store: store).syncComic(comic);

    final snapshot = await store.loadComicSnapshot('chap-1');
    final summary = await store.loadPageOrderSummary('chap-1');

    expect(snapshot, isNotNull);
    expect(snapshot!.chapters.map((e) => e.id), [
      'chap-1:Chapter/1',
      'chap-1:Chapter:2',
    ]);
    expect(await store.countPagesForChapter('chap-1:Chapter/1'), 2);
    expect(await store.countPagesForChapter('chap-1:Chapter:2'), 1);
    expect(summary.totalOrders, 2);
    expect(summary.totalPageCount, 3);
  });
}
