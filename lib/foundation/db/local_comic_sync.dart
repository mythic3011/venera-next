import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:venera/foundation/local.dart';
import 'package:venera/utils/import_sort.dart';

import 'unified_comics_store.dart';

const String canonicalLocalFallbackChapterId = '__imported__';
const String canonicalLocalDefaultPageOrderName = 'Source Default';

class LocalComicCanonicalSyncService {
  const LocalComicCanonicalSyncService({required this.store});

  final UnifiedComicsStore store;

  Future<void> syncComic(LocalComic comic) async {
    final importedAt = comic.createdAt.toIso8601String();
    final chapterInputs = await _buildChapterInputs(comic);
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
          coverLocalPath: comic.coverFile.existsSync() ? comic.coverFile.path : null,
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
          localRootPath: comic.baseDir,
          importedFromPath: comic.baseDir,
          fileCount: fileCount,
          totalBytes: totalBytes,
          importedAt: importedAt,
          updatedAt: importedAt,
        ),
      );
      await store.deleteChaptersForComic(comic.id);

      for (var chapterIndex = 0; chapterIndex < chapterInputs.length; chapterIndex++) {
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
            orderName: canonicalLocalDefaultPageOrderName,
            normalizedOrderName: _normalizeText(canonicalLocalDefaultPageOrderName),
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

  Future<List<_ImportedChapterInput>> _buildChapterInputs(LocalComic comic) async {
    if (comic.chapters == null || comic.downloadedChapters.isEmpty) {
      return [
        _ImportedChapterInput(
          sourceChapterId: canonicalLocalFallbackChapterId,
          chapterId: '${comic.id}:$canonicalLocalFallbackChapterId',
          title: comic.title,
          pages: await _listPages(Directory(comic.baseDir)),
        ),
      ];
    }

    final inputs = <_ImportedChapterInput>[];
    final chapterMap = comic.chapters!.allChapters;
    for (final sourceChapterId in comic.downloadedChapters) {
      final chapterDirectoryName = LocalManager.getChapterDirectoryName(
        sourceChapterId,
      );
      final chapterDirectory = Directory(
        p.join(comic.baseDir, chapterDirectoryName),
      );
      if (!chapterDirectory.existsSync()) {
        continue;
      }
      inputs.add(
        _ImportedChapterInput(
          sourceChapterId: sourceChapterId,
          chapterId: '${comic.id}:$sourceChapterId',
          title: chapterMap[sourceChapterId] ?? sourceChapterId,
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
      pages.add(_ImportedPageInput(path: entity.path, bytes: stat.size));
    }
    pages.sort((a, b) => naturalCompare(pathBasename(a.path), pathBasename(b.path)));
    return pages;
  }
}

class _ImportedChapterInput {
  const _ImportedChapterInput({
    required this.sourceChapterId,
    required this.chapterId,
    required this.title,
    required this.pages,
  });

  final String sourceChapterId;
  final String chapterId;
  final String title;
  final List<_ImportedPageInput> pages;
}

class _ImportedPageInput {
  const _ImportedPageInput({required this.path, required this.bytes});

  final String path;
  final int bytes;
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
