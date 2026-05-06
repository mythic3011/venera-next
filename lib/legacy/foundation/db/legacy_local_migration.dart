import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/utils/import_sort.dart';

import 'unified_comics_store.dart';

const String legacyLocalChapterFallbackId = '__imported__';
const String legacyLocalPageOrderName = 'Source Default';

class LegacyLocalMigrationReport {
  const LegacyLocalMigrationReport({
    required this.sourceDbPath,
    required this.targetDbPath,
    required this.comicsImported,
    required this.localLibraryItemsImported,
    required this.chaptersImported,
    required this.pagesImported,
    required this.pageOrdersImported,
  });

  final String sourceDbPath;
  final String targetDbPath;
  final int comicsImported;
  final int localLibraryItemsImported;
  final int chaptersImported;
  final int pagesImported;
  final int pageOrdersImported;
}

class LegacyLocalMigrationService {
  const LegacyLocalMigrationService();

  Future<LegacyLocalMigrationReport> importLocalDb({
    required UnifiedComicsStore store,
    required String legacyDbPath,
    required String localLibraryRootPath,
  }) async {
    final dbFile = File(legacyDbPath);
    if (!dbFile.existsSync()) {
      throw ArgumentError.value(legacyDbPath, 'legacyDbPath', 'File not found');
    }

    final legacyDb = sqlite.sqlite3.open(legacyDbPath);
    try {
      final comicRows = legacyDb.select('''
        SELECT
          id,
          title,
          subtitle,
          tags,
          directory,
          chapters,
          cover,
          comic_type,
          downloadedChapters,
          created_at
        FROM comics
        ORDER BY created_at ASC, title ASC;
        ''');

      var comicsImported = 0;
      var localLibraryItemsImported = 0;
      var chaptersImported = 0;
      var pagesImported = 0;
      var pageOrdersImported = 0;

      for (final row in comicRows) {
        final legacyComic = _LegacyLocalComicRow.fromRow(
          row,
          localLibraryRootPath: localLibraryRootPath,
        );
        final imported = await _importOneComic(store, legacyComic);
        comicsImported += 1;
        localLibraryItemsImported += 1;
        chaptersImported += imported.chaptersImported;
        pagesImported += imported.pagesImported;
        pageOrdersImported += imported.pageOrdersImported;
      }

      return LegacyLocalMigrationReport(
        sourceDbPath: legacyDbPath,
        targetDbPath: store.dbPath,
        comicsImported: comicsImported,
        localLibraryItemsImported: localLibraryItemsImported,
        chaptersImported: chaptersImported,
        pagesImported: pagesImported,
        pageOrdersImported: pageOrdersImported,
      );
    } finally {
      legacyDb.dispose();
    }
  }

  Future<_ImportedComicCounts> _importOneComic(
    UnifiedComicsStore store,
    _LegacyLocalComicRow legacyComic,
  ) async {
    final importedAt = _isoTimestamp(legacyComic.createdAt);
    final chapterInputs = await _buildChapterInputs(legacyComic);
    final coverPath = legacyComic.coverPath?.existsSync() ?? false
        ? legacyComic.coverPath!.path
        : null;
    final fileCount = chapterInputs.fold<int>(
      0,
      (total, chapter) => total + chapter.pages.length,
    );
    final totalBytes = chapterInputs.fold<int>(
      0,
      (total, chapter) =>
          total + chapter.pages.fold<int>(0, (sum, page) => sum + page.bytes),
    );

    await store.transaction(() async {
      await store.upsertComic(
        ComicRecord(
          id: legacyComic.comicId,
          title: legacyComic.title,
          normalizedTitle: _normalizeText(legacyComic.title),
          coverLocalPath: coverPath,
          createdAt: importedAt,
          updatedAt: importedAt,
        ),
      );
      await store.deleteComicTitlesForComic(legacyComic.comicId);
      await store.insertComicTitle(
        ComicTitleRecord(
          comicId: legacyComic.comicId,
          title: legacyComic.title,
          normalizedTitle: _normalizeText(legacyComic.title),
          titleType: 'primary',
          createdAt: importedAt,
        ),
      );
      await store.upsertLocalLibraryItem(
        LocalLibraryItemRecord(
          id: legacyComic.localLibraryItemId,
          comicId: legacyComic.comicId,
          storageType: 'user_imported',
          localRootPath: legacyComic.baseDir.path,
          importedFromPath: legacyComic.baseDir.path,
          fileCount: fileCount,
          totalBytes: totalBytes,
          importedAt: importedAt,
          updatedAt: importedAt,
        ),
      );

      for (
        var chapterIndex = 0;
        chapterIndex < chapterInputs.length;
        chapterIndex++
      ) {
        final chapter = chapterInputs[chapterIndex];
        final chapterNo =
            chapterInputs.length == 1 &&
                chapter.legacyChapterId == legacyLocalChapterFallbackId
            ? 1.0
            : (chapterIndex + 1).toDouble();
        await store.upsertChapter(
          ChapterRecord(
            id: chapter.chapterId,
            comicId: legacyComic.comicId,
            chapterNo: chapterNo,
            title: chapter.title,
            normalizedTitle: _normalizeText(chapter.title),
            createdAt: importedAt,
            updatedAt: importedAt,
          ),
        );
        for (var pageIndex = 0; pageIndex < chapter.pages.length; pageIndex++) {
          final page = chapter.pages[pageIndex];
          await store.upsertPage(
            PageRecord(
              id: '${chapter.chapterId}:$pageIndex',
              chapterId: chapter.chapterId,
              pageIndex: pageIndex,
              localPath: page.path,
              bytes: page.bytes,
              createdAt: importedAt,
            ),
          );
        }
        final orderId = '${chapter.chapterId}:source_default';
        await store.upsertPageOrder(
          PageOrderRecord(
            id: orderId,
            chapterId: chapter.chapterId,
            orderName: legacyLocalPageOrderName,
            normalizedOrderName: _normalizeText(legacyLocalPageOrderName),
            orderType: 'source_default',
            isActive: true,
            createdAt: importedAt,
            updatedAt: importedAt,
          ),
        );
        await store.replacePageOrderItems(orderId, [
          for (var pageIndex = 0; pageIndex < chapter.pages.length; pageIndex++)
            PageOrderItemRecord(
              pageOrderId: orderId,
              pageId: '${chapter.chapterId}:$pageIndex',
              sortOrder: pageIndex,
            ),
        ]);
      }
    });

    return _ImportedComicCounts(
      chaptersImported: chapterInputs.length,
      pagesImported: fileCount,
      pageOrdersImported: chapterInputs.length,
    );
  }

  Future<List<_ImportedChapterInput>> _buildChapterInputs(
    _LegacyLocalComicRow legacyComic,
  ) async {
    if (legacyComic.chapters.isEmpty) {
      final pages = await _listChapterPages(legacyComic.baseDir);
      return <_ImportedChapterInput>[
        _ImportedChapterInput(
          legacyChapterId: legacyLocalChapterFallbackId,
          chapterId: '${legacyComic.comicId}:$legacyLocalChapterFallbackId',
          title: 'Imported',
          pages: pages,
        ),
      ];
    }

    final chapters = <_ImportedChapterInput>[];
    var chapterIndex = 0;
    for (final entry in legacyComic.chapters.entries) {
      final chapterDir = Directory(
        p.join(
          legacyComic.baseDir.path,
          _sanitizeLegacyChapterDirectory(entry.key),
        ),
      );
      final pages = await _listChapterPages(chapterDir);
      chapters.add(
        _ImportedChapterInput(
          legacyChapterId: entry.key,
          chapterId: '${legacyComic.comicId}:${chapterIndex}_${entry.key}',
          title: entry.value,
          pages: pages,
        ),
      );
      chapterIndex += 1;
    }
    return chapters;
  }

  Future<List<_ImportedPageInput>> _listChapterPages(Directory dir) async {
    if (!dir.existsSync()) {
      return const <_ImportedPageInput>[];
    }
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      if (p.basename(entity.path).startsWith('cover.')) {
        continue;
      }
      if (isHiddenOrMacMetadataPath(entity.path)) {
        continue;
      }
      if (!_isImageExtension(entity.path)) {
        continue;
      }
      files.add(entity);
    }
    naturalSortFiles(files);
    return [
      for (final file in files)
        _ImportedPageInput(path: file.path, bytes: file.lengthSync()),
    ];
  }
}

class _LegacyLocalComicRow {
  const _LegacyLocalComicRow({
    required this.legacyId,
    required this.comicTypeValue,
    required this.title,
    required this.baseDir,
    required this.coverRelativePath,
    required this.chapters,
    required this.createdAt,
  });

  factory _LegacyLocalComicRow.fromRow(
    sqlite.Row row, {
    required String localLibraryRootPath,
  }) {
    final legacyId = row['id'] as String;
    final directory = row['directory'] as String;
    final chaptersJson = jsonDecode(row['chapters'] as String);
    final chapterMap = _flattenChapters(chaptersJson);
    return _LegacyLocalComicRow(
      legacyId: legacyId,
      comicTypeValue: row['comic_type'] as int,
      title: row['title'] as String,
      baseDir: _resolveLegacyBaseDir(directory, localLibraryRootPath),
      coverRelativePath: row['cover'] as String,
      chapters: chapterMap,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
    );
  }

  final String legacyId;
  final int comicTypeValue;
  final String title;
  final Directory baseDir;
  final String coverRelativePath;
  final Map<String, String> chapters;
  final DateTime createdAt;

  String get comicId => 'legacy_local:$comicTypeValue:$legacyId';

  String get localLibraryItemId =>
      'legacy_local_item:$comicTypeValue:$legacyId';

  File? get coverPath {
    final file = File(p.join(baseDir.path, coverRelativePath));
    return file.existsSync() ? file : null;
  }
}

class _ImportedComicCounts {
  const _ImportedComicCounts({
    required this.chaptersImported,
    required this.pagesImported,
    required this.pageOrdersImported,
  });

  final int chaptersImported;
  final int pagesImported;
  final int pageOrdersImported;
}

class _ImportedChapterInput {
  const _ImportedChapterInput({
    required this.legacyChapterId,
    required this.chapterId,
    required this.title,
    required this.pages,
  });

  final String legacyChapterId;
  final String chapterId;
  final String title;
  final List<_ImportedPageInput> pages;
}

class _ImportedPageInput {
  const _ImportedPageInput({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

Map<String, String> _flattenChapters(dynamic json) {
  if (json == null) {
    return const <String, String>{};
  }
  if (json is! Map) {
    return const <String, String>{};
  }
  final flat = <String, String>{};
  for (final entry in json.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (value is Map) {
      for (final grouped in value.entries) {
        flat[grouped.key.toString()] = grouped.value.toString();
      }
    } else {
      flat[key] = value.toString();
    }
  }
  return flat;
}

Directory _resolveLegacyBaseDir(
  String rawDirectory,
  String localLibraryRootPath,
) {
  if (rawDirectory.contains('/') || rawDirectory.contains(r'\')) {
    return Directory(rawDirectory);
  }
  return Directory(p.join(localLibraryRootPath, rawDirectory));
}

String _normalizeText(String value) {
  return value.trim().toLowerCase();
}

String _isoTimestamp(DateTime value) {
  return value.toUtc().toIso8601String();
}

String _sanitizeLegacyChapterDirectory(String name) {
  const invalidChars = <String>{'/', r'\', ':', '*', '?', '"', '<', '>', '|'};
  final buffer = StringBuffer();
  for (final char in name.split('')) {
    buffer.write(invalidChars.contains(char) ? '_' : char);
  }
  return buffer.toString();
}

bool _isImageExtension(String path) {
  const supported = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  };
  return supported.contains(p.extension(path).toLowerCase());
}
