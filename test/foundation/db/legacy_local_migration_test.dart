import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/foundation/db/legacy_local_migration.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  late Directory tempDir;
  late Directory localRootDir;
  late String legacyDbPath;
  late UnifiedComicsStore store;
  const migration = LegacyLocalMigrationService();

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('venera-legacy-local-test-');
    localRootDir = Directory(p.join(tempDir.path, 'local'))..createSync();
    legacyDbPath = p.join(tempDir.path, 'local.db');
    _createLegacyLocalDb(legacyDbPath);
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

  test('imports legacy local db into canonical venera.db', () async {
    _seedLegacyChapterComic(localRootDir);

    final report = await migration.importLocalDb(
      store: store,
      legacyDbPath: legacyDbPath,
      localLibraryRootPath: localRootDir.path,
    );

    final snapshot = await store.loadComicSnapshot('legacy_local:0:comic-1');
    final summary = await store.loadPageOrderSummary('legacy_local:0:comic-1');

    expect(report.sourceDbPath, legacyDbPath);
    expect(report.targetDbPath, store.dbPath);
    expect(report.comicsImported, 1);
    expect(report.localLibraryItemsImported, 1);
    expect(report.chaptersImported, 2);
    expect(report.pagesImported, 3);
    expect(report.pageOrdersImported, 2);

    expect(snapshot, isNotNull);
    expect(snapshot!.comic.title, 'Legacy Comic');
    expect(
      snapshot.localLibraryItems.single.localRootPath,
      p.join(localRootDir.path, 'Legacy Comic'),
    );
    expect(snapshot.chapters.map((chapter) => chapter.title).toList(), [
      'Chapter 1',
      'Chapter 2',
    ]);
    expect(summary.totalOrders, 2);
    expect(summary.totalPageCount, 3);
    expect(summary.visiblePageCount, 3);
  });

  test('import is idempotent for reruns into the same canonical db', () async {
    _seedLegacyFlatComic(localRootDir);

    await migration.importLocalDb(
      store: store,
      legacyDbPath: legacyDbPath,
      localLibraryRootPath: localRootDir.path,
    );
    await migration.importLocalDb(
      store: store,
      legacyDbPath: legacyDbPath,
      localLibraryRootPath: localRootDir.path,
    );

    final snapshot = await store.loadComicSnapshot('legacy_local:0:comic-flat');
    final summary = await store.loadPageOrderSummary(
      'legacy_local:0:comic-flat',
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.titles.length, 1);
    expect(snapshot.chapters.single.title, 'Imported');
    expect(summary.totalOrders, 1);
    expect(summary.totalPageCount, 2);
  });
}

void _createLegacyLocalDb(String path) {
  final db = sqlite.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE comics (
        id TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT NOT NULL,
        tags TEXT NOT NULL,
        directory TEXT NOT NULL,
        chapters TEXT NOT NULL,
        cover TEXT NOT NULL,
        comic_type INTEGER NOT NULL,
        downloadedChapters TEXT NOT NULL,
        created_at INTEGER,
        PRIMARY KEY (id, comic_type)
      );
    ''');
  } finally {
    db.dispose();
  }
}

void _seedLegacyChapterComic(Directory localRootDir) {
  final comicDir = Directory(p.join(localRootDir.path, 'Legacy Comic'))
    ..createSync(recursive: true);
  File(p.join(comicDir.path, 'cover.jpg')).writeAsBytesSync([1, 2, 3]);
  final chapter1Dir = Directory(p.join(comicDir.path, 'ch1'))..createSync();
  final chapter2Dir = Directory(p.join(comicDir.path, 'ch2'))..createSync();
  File(p.join(chapter1Dir.path, '1.jpg')).writeAsBytesSync([1]);
  File(p.join(chapter1Dir.path, '2.jpg')).writeAsBytesSync([1, 2]);
  File(p.join(chapter2Dir.path, '1.jpg')).writeAsBytesSync([1, 2, 3]);

  final db = sqlite.sqlite3.open(p.join(localRootDir.parent.path, 'local.db'));
  try {
    db.execute('INSERT INTO comics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
      'comic-1',
      'Legacy Comic',
      '',
      '[]',
      'Legacy Comic',
      '{"ch1":"Chapter 1","ch2":"Chapter 2"}',
      'cover.jpg',
      0,
      '["ch1","ch2"]',
      DateTime.utc(2026, 4, 30).millisecondsSinceEpoch,
    ]);
  } finally {
    db.dispose();
  }
}

void _seedLegacyFlatComic(Directory localRootDir) {
  final comicDir = Directory(p.join(localRootDir.path, 'Flat Comic'))
    ..createSync(recursive: true);
  File(p.join(comicDir.path, 'cover.png')).writeAsBytesSync([1, 2, 3]);
  File(p.join(comicDir.path, '1.png')).writeAsBytesSync([1]);
  File(p.join(comicDir.path, '2.png')).writeAsBytesSync([1, 2]);

  final db = sqlite.sqlite3.open(p.join(localRootDir.parent.path, 'local.db'));
  try {
    db.execute('INSERT INTO comics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
      'comic-flat',
      'Flat Comic',
      '',
      '[]',
      'Flat Comic',
      'null',
      'cover.png',
      0,
      '[]',
      DateTime.utc(2026, 4, 30).millisecondsSinceEpoch,
    ]);
  } finally {
    db.dispose();
  }
}
