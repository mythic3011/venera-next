import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/db/favorites_store.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late Database db;
  late FavoritesStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('venera-fav-store-test-');
    dbPath = '${tempDir.path}/local_favorite.db';
    db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE "src" (
        id TEXT,
        name TEXT,
        author TEXT,
        type INTEGER,
        tags TEXT,
        cover_path TEXT,
        time TEXT,
        translated_tags TEXT,
        display_order INTEGER,
        last_update_time TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE "dst" (
        id TEXT,
        name TEXT,
        author TEXT,
        type INTEGER,
        tags TEXT,
        cover_path TEXT,
        time TEXT,
        translated_tags TEXT,
        display_order INTEGER,
        last_update_time TEXT
      );
    ''');
    store = FavoritesStore(dbPath);
  });

  tearDown(() async {
    await store.close();
    db.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  FavoriteComicRecord comic({
    required String id,
    int type = 7,
    String name = 'n',
    String author = 'a',
    String tags = 't1,t2',
    String coverPath = '/c.jpg',
    String time = '2026-01-01 00:00:00',
  }) {
    return FavoriteComicRecord(
      id: id,
      name: name,
      author: author,
      type: type,
      tags: tags,
      coverPath: coverPath,
      time: time,
    );
  }

  test('insertComic sets row and optional last_update_time', () {
    store.insertComic(
      'src',
      comic(id: 'c1'),
      'tr1,tr2',
      10,
      updateTime: '2026-02-02 10:00:00',
    );

    final row = db
        .select('select * from "src" where id = ? and type = ?;', ['c1', 7])
        .single;
    expect(row['display_order'], 10);
    expect(row['translated_tags'], 'tr1,tr2');
    expect(row['last_update_time'], '2026-02-02 10:00:00');
  });

  test('deleteComic removes one row by id+type', () {
    store.insertComic('src', comic(id: 'c1'), 'tr', 1);
    store.insertComic('src', comic(id: 'c1', type: 8), 'tr', 2);

    store.deleteComic('src', 'c1', 7);

    final rows = db.select('select id, type from "src" order by type;');
    expect(rows.length, 1);
    expect(rows.single['type'], 8);
  });

  test('batchDeleteComics deletes all requested rows in one folder', () {
    store.insertComic('src', comic(id: 'a'), 'tr', 1);
    store.insertComic('src', comic(id: 'b'), 'tr', 2);
    store.insertComic('src', comic(id: 'c'), 'tr', 3);

    store.batchDeleteComics('src', [comic(id: 'a'), comic(id: 'c')]);

    final ids = db
        .select('select id from "src" order by display_order;')
        .map((r) => r['id'])
        .toList();
    expect(ids, ['b']);
  });

  test('moveFavorite inserts to target with provided order and deletes source', () {
    store.insertComic('src', comic(id: 'm1'), 'tr', 4);

    store.moveFavorite('src', 'dst', 'm1', 7, -3);

    expect(db.select('select * from "src";'), isEmpty);
    final moved = db.select('select * from "dst" where id = ?;', ['m1']).single;
    expect(moved['display_order'], -3);
  });

  test('batchMoveFavorites uses increasing order and remove from source', () {
    store.insertComic('src', comic(id: 'm1'), 'tr', 1);
    store.insertComic('src', comic(id: 'm2'), 'tr', 2);

    store.batchMoveFavorites(
      'src',
      'dst',
      [comic(id: 'm1'), comic(id: 'm2')],
      100,
    );

    expect(db.select('select * from "src";'), isEmpty);
    final dstRows = db.select('select id, display_order from "dst" order by display_order;');
    expect(dstRows.length, 2);
    expect(dstRows[0]['id'], 'm1');
    expect(dstRows[0]['display_order'], 100);
    expect(dstRows[1]['id'], 'm2');
    expect(dstRows[1]['display_order'], 101);
  });

  test('batchCopyFavorites keeps source; insert-or-ignore follows table constraints', () {
    store.insertComic('src', comic(id: 'c1'), 'tr', 1);
    store.insertComic('src', comic(id: 'c2'), 'tr', 2);
    db.execute(
      '''
      insert into "dst" (id, name, author, type, tags, cover_path, time, translated_tags, display_order)
      values (?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      ['c1', 'existing', 'a', 7, 't', '/x.jpg', '2026-01-01 00:00:00', 'tr', 5],
    );

    store.batchCopyFavorites(
      'src',
      'dst',
      [comic(id: 'c1'), comic(id: 'c2')],
      20,
    );

    expect(db.select('select id from "src" order by id;').length, 2);
    final dstRows = db.select(
      'select id, display_order from "dst" order by display_order;',
    );
    expect(dstRows.length, 3);
    expect(dstRows[0]['id'], 'c1');
    expect(dstRows[0]['display_order'], 5);
    expect(dstRows[1]['id'], 'c1');
    expect(dstRows[1]['display_order'], 20);
    expect(dstRows[2]['id'], 'c2');
    expect(dstRows[2]['display_order'], 21);
  });

  test('order and schema helpers reflect table state', () {
    store.insertComic('src', comic(id: 'x1'), 'tr', -2);
    store.insertComic('src', comic(id: 'x2'), 'tr', 9);

    expect(store.minDisplayOrder('src'), -2);
    expect(store.maxDisplayOrder('src'), 9);
    expect(store.hasColumn('src', 'last_update_time'), isTrue);
    expect(store.hasColumn('src', 'missing_col'), isFalse);
    expect(store.hasComic('src', 'x1', 7), isTrue);
    expect(store.hasComic('src', 'x1', 999), isFalse);
  });
}
