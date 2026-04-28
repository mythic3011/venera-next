import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

class FavoriteComicRecord {
  final String id;
  final String name;
  final String author;
  final int type;
  final String tags;
  final String coverPath;
  final String time;

  const FavoriteComicRecord({
    required this.id,
    required this.name,
    required this.author,
    required this.type,
    required this.tags,
    required this.coverPath,
    required this.time,
  });
}

class FavoritesStore extends GeneratedDatabase {
  final Database _syncDb;

  FavoritesStore(String dbPath)
    : _syncDb = sqlite3.open(dbPath),
      super(NativeDatabase.createInBackground(File(dbPath)));

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  Future<List<String>> listTables() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table';",
    ).get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<List<FavoriteComicRecord>> loadFolderComics(String folder) async {
    final rows = await customSelect(
      'select * from "$folder" ORDER BY display_order;',
    ).get();
    return rows
        .map(
          (r) => FavoriteComicRecord(
            id: r.read<String>('id'),
            name: r.read<String>('name'),
            author: r.read<String>('author'),
            type: r.read<int>('type'),
            tags: r.read<String>('tags'),
            coverPath: r.read<String>('cover_path'),
            time: r.read<String>('time'),
          ),
        )
        .toList();
  }

  Future<Map<int, int>> loadHashedIds(List<String> folders) async {
    final hashed = <int, int>{};
    for (final folder in folders) {
      final rows = await customSelect('select id, type from "$folder";').get();
      for (final row in rows) {
        final id = row.read<String>('id');
        final type = row.read<int>('type');
        final hash = id.hashCode ^ type;
        hashed[hash] = (hashed[hash] ?? 0) + 1;
      }
    }
    return hashed;
  }

  int maxDisplayOrder(String folder) {
    return _syncDb.select("""
      SELECT MAX(display_order) AS max_value
      FROM "$folder";
    """).firstOrNull?["max_value"] ??
        0;
  }

  int minDisplayOrder(String folder) {
    return _syncDb.select("""
      SELECT MIN(display_order) AS min_value
      FROM "$folder";
    """).firstOrNull?["min_value"] ??
        0;
  }

  bool hasColumn(String folder, String columnName) {
    final columns = _syncDb.select('pragma table_info("$folder");');
    return columns.any((element) => element["name"] == columnName);
  }

  bool hasComic(String folder, String id, int type) {
    final rows = _syncDb.select(
      """
      select * from "$folder"
      where id == ? and type == ?;
    """,
      [id, type],
    );
    return rows.isNotEmpty;
  }

  void insertComic(
    String folder,
    FavoriteComicRecord comic,
    String translatedTags,
    int displayOrder, {
    String? updateTime,
  }) {
    _syncDb.execute(
      """
      insert into "$folder" (id, name, author, type, tags, cover_path, time, translated_tags, display_order)
      values (?, ?, ?, ?, ?, ?, ?, ?, ?);
    """,
      [
        comic.id,
        comic.name,
        comic.author,
        comic.type,
        comic.tags,
        comic.coverPath,
        comic.time,
        translatedTags,
        displayOrder,
      ],
    );
    if (updateTime != null && hasColumn(folder, "last_update_time")) {
      _syncDb.execute(
        """
        update "$folder"
        set last_update_time = ?
        where id == ? and type == ?;
      """,
        [updateTime, comic.id, comic.type],
      );
    }
  }

  void deleteComic(String folder, String id, int type) {
    _syncDb.execute(
      """
      delete from "$folder"
      where id == ? and type == ?;
    """,
      [id, type],
    );
  }

  void batchDeleteComics(String folder, List<FavoriteComicRecord> comics) {
    _syncDb.execute("BEGIN TRANSACTION");
    try {
      for (final comic in comics) {
        deleteComic(folder, comic.id, comic.type);
      }
    } catch (_) {
      _syncDb.execute("ROLLBACK");
      rethrow;
    }
    _syncDb.execute("COMMIT");
  }

  void moveFavorite(
    String sourceFolder,
    String targetFolder,
    String id,
    int type,
    int targetDisplayOrder,
  ) {
    _syncDb.execute(
      """
      insert into "$targetFolder" (id, name, author, type, tags, cover_path, time, display_order)
      select id, name, author, type, tags, cover_path, time, ?
      from "$sourceFolder"
      where id == ? and type == ?;
    """,
      [targetDisplayOrder, id, type],
    );
    deleteComic(sourceFolder, id, type);
  }

  void batchMoveFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteComicRecord> comics,
    int startDisplayOrder,
  ) {
    _syncDb.execute("BEGIN TRANSACTION");
    var displayOrder = startDisplayOrder;
    try {
      for (final comic in comics) {
        _syncDb.execute(
          """
          insert or ignore into "$targetFolder" (id, name, author, type, tags, cover_path, time, display_order)
          select id, name, author, type, tags, cover_path, time, ?
          from "$sourceFolder"
          where id == ? and type == ?;
        """,
          [displayOrder, comic.id, comic.type],
        );
        deleteComic(sourceFolder, comic.id, comic.type);
        displayOrder++;
      }
    } catch (_) {
      _syncDb.execute("ROLLBACK");
      rethrow;
    }
    _syncDb.execute("COMMIT");
  }

  void batchCopyFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteComicRecord> comics,
    int startDisplayOrder,
  ) {
    _syncDb.execute("BEGIN TRANSACTION");
    var displayOrder = startDisplayOrder;
    try {
      for (final comic in comics) {
        _syncDb.execute(
          """
          insert or ignore into "$targetFolder" (id, name, author, type, tags, cover_path, time, display_order)
          select id, name, author, type, tags, cover_path, time, ?
          from "$sourceFolder"
          where id == ? and type == ?;
        """,
          [displayOrder, comic.id, comic.type],
        );
        displayOrder++;
      }
    } catch (_) {
      _syncDb.execute("ROLLBACK");
      rethrow;
    }
    _syncDb.execute("COMMIT");
  }

  @override
  Future<void> close() async {
    _syncDb.dispose();
    await super.close();
  }
}
