import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class LocalComicRecord {
  final String id;
  final String title;
  final String subtitle;
  final List<String> tags;
  final String directory;
  final String chaptersJson;
  final String cover;
  final int comicType;
  final List<String> downloadedChapters;
  final int createdAtMillis;

  const LocalComicRecord({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.directory,
    required this.chaptersJson,
    required this.cover,
    required this.comicType,
    required this.downloadedChapters,
    required this.createdAtMillis,
  });
}

class LocalComicsStore extends GeneratedDatabase {
  LocalComicsStore(String dbPath)
    : super(NativeDatabase.createInBackground(File(dbPath)));

  Future<void> init() async {
    await _customStatement('''
      CREATE TABLE IF NOT EXISTS comics (
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
  }

  @override
  Future<void> close() async {
    await super.close();
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  Future<List<LocalComicRecord>> loadAll() async {
    final rows = await _customSelect('SELECT * FROM comics;');
    return rows
        .map(
          (row) => LocalComicRecord(
            id: row.read<String>('id'),
            title: row.read<String>('title'),
            subtitle: row.read<String>('subtitle'),
            tags: List<String>.from(jsonDecode(row.read<String>('tags'))),
            directory: row.read<String>('directory'),
            chaptersJson: row.read<String>('chapters'),
            cover: row.read<String>('cover'),
            comicType: row.read<int>('comic_type'),
            downloadedChapters: List<String>.from(
              jsonDecode(row.read<String>('downloadedChapters')),
            ),
            createdAtMillis: row.read<int>('created_at'),
          ),
        )
        .toList();
  }

  Future<void> upsert(LocalComicRecord record) async {
    await _customStatement(
      'INSERT OR REPLACE INTO comics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        record.id,
        record.title,
        record.subtitle,
        jsonEncode(record.tags),
        record.directory,
        record.chaptersJson,
        record.cover,
        record.comicType,
        jsonEncode(record.downloadedChapters),
        record.createdAtMillis,
      ],
    );
  }

  Future<void> deleteComic(String id, int comicType) async {
    await _customStatement(
      'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
      [id, comicType],
    );
  }

  Future<void> updateCover(String id, int comicType, String cover) async {
    await _customStatement(
      'UPDATE comics SET cover = ? WHERE id = ? AND comic_type = ?;',
      [cover, id, comicType],
    );
  }

  Future<void> updateChapters(
    String id,
    int comicType,
    String chaptersJson,
    String downloadedChaptersJson,
  ) async {
    await _customStatement(
      'UPDATE comics SET chapters = ?, downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
      [chaptersJson, downloadedChaptersJson, id, comicType],
    );
  }

  Future<void> updateChaptersOnly(
    String id,
    int comicType,
    String chaptersJson,
  ) async {
    await _customStatement(
      'UPDATE comics SET chapters = ? WHERE id = ? AND comic_type = ?;',
      [chaptersJson, id, comicType],
    );
  }

  Future<void> batchDelete(List<(String id, int comicType)> keys) async {
    await transaction(() async {
      for (final key in keys) {
        await _customStatement(
          'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
          [key.$1, key.$2],
        );
      }
    });
  }

  Future<void> _customStatement(
    String sql, [
    List<Object?> variables = const [],
  ]) {
    return customStatement(sql, variables);
  }

  Future<List<QueryRow>> _customSelect(
    String sql, [
    List<Variable<Object>> variables = const [],
  ]) {
    return customSelect(sql, variables: variables).get();
  }
}
