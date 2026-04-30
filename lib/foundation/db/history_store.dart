import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class HistoryRecord {
  final String id;
  final String title;
  final String subtitle;
  final String cover;
  final int timeMillis;
  final int type;
  final int ep;
  final int page;
  final String readEpisode;
  final int? maxPage;
  final int? chapterGroup;

  const HistoryRecord({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.timeMillis,
    required this.type,
    required this.ep,
    required this.page,
    required this.readEpisode,
    required this.maxPage,
    required this.chapterGroup,
  });
}

class ImageFavoriteRecord {
  final String id;
  final String title;
  final String subTitle;
  final String author;
  final String tags;
  final String translatedTags;
  final int timeMillis;
  final int maxPage;
  final String sourceKey;
  final String imageFavoritesEpJson;
  final String otherJson;

  const ImageFavoriteRecord({
    required this.id,
    required this.title,
    required this.subTitle,
    required this.author,
    required this.tags,
    required this.translatedTags,
    required this.timeMillis,
    required this.maxPage,
    required this.sourceKey,
    required this.imageFavoritesEpJson,
    required this.otherJson,
  });
}

class HistoryStore extends GeneratedDatabase {
  // Legacy DB access. Do not call from reader/home/history runtime paths.
  HistoryStore(String dbPath)
    : super(NativeDatabase.createInBackground(File(dbPath)));

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  Future<void> init() async {
    await customStatement('''
      create table if not exists history  (
        id text primary key,
        title text,
        subtitle text,
        cover text,
        time int,
        type int,
        ep int,
        page int,
        readEpisode text,
        max_page int,
        chapter_group int
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS image_favorites (
        id TEXT,
        title TEXT NOT NULL,
        sub_title TEXT,
        author TEXT,
        tags TEXT,
        translated_tags TEXT,
        time int,
        max_page int,
        source_key TEXT NOT NULL,
        image_favorites_ep TEXT NOT NULL,
        other TEXT NOT NULL,
        PRIMARY KEY (id,source_key)
      );
    ''');
  }

  Future<List<HistoryRecord>> loadAllHistory() async {
    final rows = await customSelect('select * from history;').get();
    return rows
        .map(
          (row) => HistoryRecord(
            id: row.read<String>('id'),
            title: row.read<String>('title'),
            subtitle: row.read<String>('subtitle'),
            cover: row.read<String>('cover'),
            timeMillis: row.read<int>('time'),
            type: row.read<int>('type'),
            ep: row.read<int>('ep'),
            page: row.read<int>('page'),
            readEpisode: row.read<String>('readEpisode'),
            maxPage: row.read<int?>('max_page'),
            chapterGroup: row.read<int?>('chapter_group'),
          ),
        )
        .toList();
  }

  Future<void> upsertHistory(HistoryRecord item) {
    return customStatement(
      '''
      insert or replace into history (id, title, subtitle, cover, time, type, ep, page, readEpisode, max_page, chapter_group)
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        item.id,
        item.title,
        item.subtitle,
        item.cover,
        item.timeMillis,
        item.type,
        item.ep,
        item.page,
        item.readEpisode,
        item.maxPage,
        item.chapterGroup,
      ],
    );
  }

  Future<void> clearHistory() => customStatement('delete from history;');

  Future<void> deleteHistory(String id, int type) {
    return customStatement('delete from history where id == ? and type == ?;', [
      id,
      type,
    ]);
  }

  Future<void> batchDeleteHistories(List<(String id, int type)> items) async {
    await transaction(() async {
      for (final item in items) {
        await customStatement(
          'delete from history where id == ? and type == ?;',
          [item.$1, item.$2],
        );
      }
    });
  }

  Future<List<ImageFavoriteRecord>> loadAllImageFavorites() async {
    final rows = await customSelect('select * from image_favorites;').get();
    return rows
        .map(
          (r) => ImageFavoriteRecord(
            id: r.read<String>('id'),
            title: r.read<String>('title'),
            subTitle: r.read<String>('sub_title'),
            author: r.read<String>('author'),
            tags: r.read<String>('tags'),
            translatedTags: r.read<String>('translated_tags'),
            timeMillis: r.read<int>('time'),
            maxPage: r.read<int>('max_page'),
            sourceKey: r.read<String>('source_key'),
            imageFavoritesEpJson: r.read<String>('image_favorites_ep'),
            otherJson: r.read<String>('other'),
          ),
        )
        .toList();
  }

  Future<void> upsertImageFavorite(ImageFavoriteRecord favorite) {
    return customStatement(
      '''
      insert or replace into image_favorites(id, title, sub_title, author, tags, translated_tags, time, max_page, source_key, image_favorites_ep, other)
      values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        favorite.id,
        favorite.title,
        favorite.subTitle,
        favorite.author,
        favorite.tags,
        favorite.translatedTags,
        favorite.timeMillis,
        favorite.maxPage,
        favorite.sourceKey,
        favorite.imageFavoritesEpJson,
        favorite.otherJson,
      ],
    );
  }

  Future<void> deleteImageFavorite(String id, String sourceKey) {
    return customStatement(
      'delete from image_favorites where id == ? and source_key == ?;',
      [id, sourceKey],
    );
  }

  Future<List<ImageFavoriteRecord>> searchImageFavorites(String keyword) async {
    final k = '%$keyword%';
    final rows = await customSelect('''
      select * from image_favorites
      WHERE title LIKE ?
      OR sub_title LIKE ?
      OR LOWER(tags) LIKE LOWER(?)
      OR LOWER(translated_tags) LIKE LOWER(?)
      OR author LIKE ?;
      ''', variables: List.generate(5, (_) => Variable<String>(k))).get();
    return rows
        .map(
          (r) => ImageFavoriteRecord(
            id: r.read<String>('id'),
            title: r.read<String>('title'),
            subTitle: r.read<String>('sub_title'),
            author: r.read<String>('author'),
            tags: r.read<String>('tags'),
            translatedTags: r.read<String>('translated_tags'),
            timeMillis: r.read<int>('time'),
            maxPage: r.read<int>('max_page'),
            sourceKey: r.read<String>('source_key'),
            imageFavoritesEpJson: r.read<String>('image_favorites_ep'),
            otherJson: r.read<String>('other'),
          ),
        )
        .toList();
  }
}
