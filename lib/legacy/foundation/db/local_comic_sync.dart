import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/utils/import_sort.dart';

import 'unified_comics_store.dart';

const String canonicalLocalFallbackChapterId = '__imported__';
const String canonicalLocalDefaultPageOrderName = 'Source Default';

class LocalComicCanonicalSyncService {
  const LocalComicCanonicalSyncService({
    required this.store,
    this.resolveCanonicalLocalRootPath,
  });

  final UnifiedComicsStore store;
  final Future<String> Function()? resolveCanonicalLocalRootPath;

  Future<void> syncComic(LocalComic comic) async {
    final canonicalLocalRootPath = await _requireCanonicalLocalRootPath();
    final comicRootPath = resolveImportedComicRootPath(
      canonicalLocalRootPath: canonicalLocalRootPath,
      comic: comic,
    );
    final coverLocalPath = resolveImportedComicCoverPath(
      comicRootPath: comicRootPath,
      cover: comic.cover,
    );
    final importedAt = comic.createdAt.toIso8601String();
    final chapterInputs = await _buildChapterInputs(comic, comicRootPath);
    final sourceLinkId = _localComicSourceLinkId(comic.id);
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
          id: comic.id,
          title: comic.title,
          normalizedTitle: _normalizeText(comic.title),
          coverLocalPath:
              coverLocalPath != null && File(coverLocalPath).existsSync()
              ? coverLocalPath
              : null,
          createdAt: importedAt,
          updatedAt: importedAt,
        ),
      );
      await store.deleteComicTitlesForComic(comic.id);
      await store.insertComicTitle(
        ComicTitleRecord(
          comicId: comic.id,
          title: comic.title,
          normalizedTitle: _normalizeText(comic.title),
          titleType: 'primary',
          createdAt: importedAt,
        ),
      );
      await store.upsertLocalLibraryItem(
        LocalLibraryItemRecord(
          id: _localLibraryItemId(comic.id),
          comicId: comic.id,
          storageType: 'user_imported',
          localRootPath: comicRootPath,
          importedFromPath: comicRootPath,
          fileCount: fileCount,
          totalBytes: totalBytes,
          importedAt: importedAt,
          updatedAt: importedAt,
        ),
      );
      await store.upsertComicSourceLink(
        ComicSourceLinkRecord(
          id: sourceLinkId,
          comicId: comic.id,
          sourcePlatformId: 'local',
          sourceComicId: comicRootPath,
          linkStatus: 'candidate',
          isPrimary: false,
          sourceUrl: Directory(comicRootPath).uri.toString(),
          sourceTitle: comic.title,
          linkedAt: importedAt,
          updatedAt: importedAt,
          metadataJson: '{"origin":"local_import"}',
        ),
      );
      await store.deleteChaptersForComic(comic.id);

      for (
        var chapterIndex = 0;
        chapterIndex < chapterInputs.length;
        chapterIndex++
      ) {
        final chapter = chapterInputs[chapterIndex];
        final chapterNo =
            chapterInputs.length == 1 &&
                chapter.sourceChapterId == canonicalLocalFallbackChapterId
            ? 1.0
            : (chapterIndex + 1).toDouble();
        await store.upsertChapter(
          ChapterRecord(
            id: chapter.chapterId,
            comicId: comic.id,
            chapterNo: chapterNo,
            title: chapter.title,
            normalizedTitle: _normalizeText(chapter.title),
            createdAt: importedAt,
            updatedAt: importedAt,
          ),
        );
        final chapterSourceLinkId =
            '$sourceLinkId:chapter:${chapter.sourceChapterId}';
        await store.upsertChapterSourceLink(
          ChapterSourceLinkRecord(
            id: chapterSourceLinkId,
            chapterId: chapter.chapterId,
            comicSourceLinkId: sourceLinkId,
            sourceChapterId: chapter.sourceChapterId,
            sourceUrl: chapter.directory.uri.toString(),
            linkedAt: importedAt,
            updatedAt: importedAt,
            metadataJson: '{"origin":"local_import"}',
          ),
        );
        for (var pageIndex = 0; pageIndex < chapter.pages.length; pageIndex++) {
          final page = chapter.pages[pageIndex];
          final pageId = '${chapter.chapterId}:$pageIndex';
          await store.upsertPage(
            PageRecord(
              id: pageId,
              chapterId: chapter.chapterId,
              pageIndex: pageIndex,
              localPath: page.path,
              bytes: page.bytes,
              createdAt: importedAt,
            ),
          );
          await store.upsertPageSourceLink(
            PageSourceLinkRecord(
              id: '$chapterSourceLinkId:page:$pageIndex',
              pageId: pageId,
              comicSourceLinkId: sourceLinkId,
              chapterSourceLinkId: chapterSourceLinkId,
              sourcePageId: page.sourcePageId,
              sourceUrl: File(page.path).uri.toString(),
              linkedAt: importedAt,
              updatedAt: importedAt,
              metadataJson: '{"origin":"local_import"}',
            ),
          );
        }
        final orderId = '${chapter.chapterId}:source_default';
        await store.upsertPageOrder(
          PageOrderRecord(
            id: orderId,
            chapterId: chapter.chapterId,
            orderName: canonicalLocalDefaultPageOrderName,
            normalizedOrderName: _normalizeText(
              canonicalLocalDefaultPageOrderName,
            ),
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
  }

  String _localLibraryItemId(String comicId) => 'local_item:$comicId';
  String _localComicSourceLinkId(String comicId) =>
      'source_link:local:$comicId';

  Future<List<_ImportedChapterInput>> _buildChapterInputs(
    LocalComic comic,
    String comicRootPath,
  ) async {
    if (comic.chapters == null || comic.downloadedChapters.isEmpty) {
      return [
        _ImportedChapterInput(
          sourceChapterId: canonicalLocalFallbackChapterId,
          chapterId: '${comic.id}:$canonicalLocalFallbackChapterId',
          title: comic.title,
          directory: Directory(comicRootPath),
          pages: await _listPages(Directory(comicRootPath)),
        ),
      ];
    }

    final inputs = <_ImportedChapterInput>[];
    final chapterMap = comic.chapters!.allChapters;
    for (final sourceChapterId in comic.downloadedChapters) {
      final chapterDirectoryName = _sanitizeChapterDirectoryName(
        sourceChapterId,
      );
      final chapterDirectory = Directory(
        p.join(comicRootPath, chapterDirectoryName),
      );
      if (!chapterDirectory.existsSync()) {
        continue;
      }
      inputs.add(
        _ImportedChapterInput(
          sourceChapterId: sourceChapterId,
          chapterId: '${comic.id}:$sourceChapterId',
          title: chapterMap[sourceChapterId] ?? sourceChapterId,
          directory: chapterDirectory,
          pages: await _listPages(chapterDirectory),
        ),
      );
    }
    return inputs;
  }

  Future<List<_ImportedPageInput>> _listPages(Directory directory) async {
    final pages = <_ImportedPageInput>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!_isSupportedImagePath(entity.path)) {
        continue;
      }
      final stat = await entity.stat();
      pages.add(
        _ImportedPageInput(
          path: entity.path,
          bytes: stat.size,
          sourcePageId: pathBasename(entity.path),
        ),
      );
    }
    pages.sort(
      (a, b) => naturalCompare(pathBasename(a.path), pathBasename(b.path)),
    );
    return pages;
  }

  Future<String> _requireCanonicalLocalRootPath() async {
    final injectedPath = await resolveCanonicalLocalRootPath?.call();
    if (injectedPath != null && injectedPath.trim().isNotEmpty) {
      return injectedPath.trim();
    }
    final configuredPath = _readPersistedCanonicalLocalRootPath();
    if (configuredPath != null && configuredPath.trim().isNotEmpty) {
      return configuredPath.trim();
    }
    final trimmedFallbackPath = '${App.dataPath}${Platform.pathSeparator}local'
        .trim();
    if (trimmedFallbackPath.isEmpty) {
      throw Exception(
        'Canonical local storage unavailable (fail closed): '
        'CANONICAL_ROOT_UNAVAILABLE',
      );
    }
    return trimmedFallbackPath;
  }
}

class _ImportedChapterInput {
  const _ImportedChapterInput({
    required this.sourceChapterId,
    required this.chapterId,
    required this.title,
    required this.directory,
    required this.pages,
  });

  final String sourceChapterId;
  final String chapterId;
  final String title;
  final Directory directory;
  final List<_ImportedPageInput> pages;
}

class _ImportedPageInput {
  const _ImportedPageInput({
    required this.path,
    required this.bytes,
    required this.sourcePageId,
  });

  final String path;
  final int bytes;
  final String sourcePageId;
}

String _normalizeText(String value) => value.trim().toLowerCase();

String pathBasename(String path) => p.basename(path);

bool _isSupportedImagePath(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' || 'jpe' => true,
    _ => false,
  };
}

String _sanitizeChapterDirectoryName(String name) {
  final builder = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final char = name[i];
    if (char == '/' ||
        char == '\\' ||
        char == ':' ||
        char == '*' ||
        char == '?' ||
        char == '"' ||
        char == '<' ||
        char == '>' ||
        char == '|') {
      builder.write('_');
    } else {
      builder.write(char);
    }
  }
  return builder.toString();
}

String? _readPersistedCanonicalLocalRootPath() {
  final file = File('${App.dataPath}${Platform.pathSeparator}local_path');
  if (!file.existsSync()) {
    return null;
  }
  final value = file.readAsStringSync().trim();
  return value.isEmpty ? null : value;
}

String resolveImportedComicRootPath({
  required String canonicalLocalRootPath,
  required LocalComic comic,
}) {
  final directory = comic.directory;
  if (p.isAbsolute(directory)) {
    return directory;
  }
  return p.join(canonicalLocalRootPath, directory);
}

String? resolveImportedComicCoverPath({
  required String comicRootPath,
  required String? cover,
}) {
  final coverPath = cover?.trim();
  if (coverPath == null || coverPath.isEmpty) {
    return null;
  }
  if (p.isAbsolute(coverPath)) {
    return coverPath;
  }
  return p.join(comicRootPath, coverPath);
}
