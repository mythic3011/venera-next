import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/foundation/db/legacy_history_migration.dart';
import 'package:venera/foundation/db/legacy_local_migration.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  late Directory tempDir;
  late Directory localRootDir;
  late String localDbPath;
  late String historyDbPath;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'venera-legacy-history-test-',
    );
    localRootDir = Directory(p.join(tempDir.path, 'local'))..createSync();
    localDbPath = p.join(tempDir.path, 'local.db');
    historyDbPath = p.join(tempDir.path, 'history.db');
    _createLegacyLocalDb(localDbPath);
    _createLegacyHistoryDb(historyDbPath);
    _seedLegacyFlatComic(localRootDir);
    _seedHistory(historyDbPath);
    store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    await store.seedDefaultSourcePlatforms();
    await const LegacyLocalMigrationService().importLocalDb(
      store: store,
      legacyDbPath: localDbPath,
      localLibraryRootPath: localRootDir.path,
    );
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'imports resolvable local history and skips missing canonical comics',
    () async {
      final report = await const LegacyHistoryMigrationService()
          .importHistoryDb(store: store, legacyDbPath: historyDbPath);

      final imported = await store.loadLatestHistoryEvent(
        'legacy_local:0:comic-flat',
      );
      final missingRemote = await store.loadLatestHistoryEvent(
        'legacy_source:123:remote-1',
      );

      expect(report.imported, 1);
      expect(report.skippedMissingComic, 1);
      expect(imported, isNotNull);
      expect(imported!.chapterIndex, 1);
      expect(imported.pageIndex, 7);
      expect(imported.chapterGroup, isNull);
      expect(missingRemote, isNull);
    },
  );
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

void _createLegacyHistoryDb(String path) {
  final db = sqlite.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE history (
        id TEXT PRIMARY KEY,
        title TEXT,
        subtitle TEXT,
        cover TEXT,
        time INT,
        type INT,
        ep INT,
        page INT,
        readEpisode TEXT,
        max_page INT,
        chapter_group INT
      );
    ''');
  } finally {
    db.dispose();
  }
}

void _seedHistory(String path) {
  final db = sqlite.sqlite3.open(path);
  try {
    db.execute(
      'INSERT INTO history VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'comic-flat',
        'Flat Comic',
        '',
        'cover.png',
        DateTime.utc(2026, 4, 30, 12).millisecondsSinceEpoch,
        0,
        1,
        7,
        '1',
        12,
        null,
      ],
    );
    db.execute(
      'INSERT INTO history VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        'remote-1',
        'Remote Only',
        '',
        'remote.jpg',
        DateTime.utc(2026, 4, 30, 13).millisecondsSinceEpoch,
        123,
        2,
        5,
        '1,2',
        20,
        null,
      ],
    );
  } finally {
    db.dispose();
  }
}
