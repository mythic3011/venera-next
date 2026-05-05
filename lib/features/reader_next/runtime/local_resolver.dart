import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/sources/identity/constants.dart';
import 'package:venera/utils/io.dart';

import 'models.dart';
import 'ports.dart';

class LegacyLocalReaderPageResolver implements LocalReaderPageResolver {
  const LegacyLocalReaderPageResolver({
    Future<List<String>> Function(String comicId, String? chapterId)?
    loadCanonicalPages,
  }) : _loadCanonicalPages = loadCanonicalPages;

  final Future<List<String>> Function(String comicId, String? chapterId)?
  _loadCanonicalPages;

  @override
  Future<List<ReaderImageRef>> loadReaderPageImages({
    required ComicIdentity identity,
    required String chapterRefId,
    required int page,
  }) async {
    final sourceRef = identity.sourceRef;
    void recordBlocked(String code, {String? fileName}) {
      AppDiagnostics.warn(
        'reader.local',
        'reader.local.render.blocked',
        data: {
          'code': code,
          'loadMode': 'local',
          'sourceKey': sourceRef.sourceKey,
          'comicId': identity.canonicalComicId,
          'chapterId': chapterRefId,
          'page': page,
          if (fileName != null) 'fileName': fileName,
        },
      );
    }

    AppDiagnostics.info(
      'reader.local',
      'reader.local.resolve.start',
      data: {
        'loadMode': 'local',
        'sourceKey': sourceRef.sourceKey,
        'comicId': identity.canonicalComicId,
        'chapterId': chapterRefId,
        'page': page,
      },
    );

    if (sourceRef.type != SourceRefType.local ||
        sourceRef.sourceKey != localSourceKey ||
        sourceRef.upstreamComicRefId.trim().isEmpty) {
      recordBlocked('LOCAL_IDENTITY_MISSING');
      throw ReaderRuntimeException(
        'LOCAL_IDENTITY_MISSING',
        'Local reader requires explicit local source identity',
      );
    }

    if (chapterRefId.trim().isEmpty) {
      recordBlocked('LOCAL_CHAPTER_NOT_FOUND');
      throw ReaderRuntimeException(
        'LOCAL_CHAPTER_NOT_FOUND',
        'Local reader chapter identity is missing',
      );
    }

    final paths = await _safeLoadCanonicalLocalPages(
      comicId: sourceRef.upstreamComicRefId,
      chapterRefId: chapterRefId,
    );
    if (paths.isEmpty) {
      recordBlocked('LOCAL_PAGES_EMPTY');
      throw ReaderRuntimeException(
        'LOCAL_PAGES_EMPTY',
        'Local chapter has no readable pages',
      );
    }
    for (final path in paths) {
      if (path.trim().isEmpty) {
        AppDiagnostics.warn(
          'reader.local',
          'reader.local.pageUri.missing',
          data: {
            'code': 'LOCAL_PAGE_FILE_MISSING',
            'loadMode': 'local',
            'sourceKey': sourceRef.sourceKey,
            'comicId': identity.canonicalComicId,
            'chapterId': chapterRefId,
            'page': page,
          },
        );
        recordBlocked('LOCAL_PAGE_FILE_MISSING');
        throw ReaderRuntimeException(
          'LOCAL_PAGE_FILE_MISSING',
          'Local reader page path is missing',
        );
      }
      final file = File(path);
      if (!await file.exists()) {
        AppDiagnostics.warn(
          'reader.local',
          'reader.local.pageUri.missing',
          data: {
            'code': 'LOCAL_PAGE_FILE_MISSING',
            'loadMode': 'local',
            'sourceKey': sourceRef.sourceKey,
            'comicId': identity.canonicalComicId,
            'chapterId': chapterRefId,
            'page': page,
            'fileName': file.name,
          },
        );
        recordBlocked('LOCAL_PAGE_FILE_MISSING', fileName: file.name);
        throw ReaderRuntimeException(
          'LOCAL_PAGE_FILE_MISSING',
          'Local reader page file does not exist',
        );
      }
    }
    final refs = List<ReaderImageRef>.generate(paths.length, (index) {
      final path = paths[index];
      return ReaderImageRef(
        imageKey: 'local:$chapterRefId:$index',
        imageUrl: path,
      );
    }, growable: false);
    AppDiagnostics.info(
      'reader.local',
      'reader.local.resolve.result',
      data: {
        'loadMode': 'local',
        'sourceKey': sourceRef.sourceKey,
        'comicId': identity.canonicalComicId,
        'chapterId': chapterRefId,
        'page': page,
        'pageCount': refs.length,
        'firstImageKey': refs.first.imageKey,
        'firstPageUriScheme': Uri.file(paths.first).scheme,
      },
    );
    return refs;
  }

  Future<List<String>> _safeLoadCanonicalLocalPages({
    required String comicId,
    required String chapterRefId,
  }) async {
    try {
      return await (_loadCanonicalPages ?? _loadCanonicalLocalPagesFromStore)
          .call(comicId, chapterRefId);
    } catch (error) {
      final message = error.toString();
      if (message.contains('CANONICAL_LOCAL_COMIC_NOT_FOUND') ||
          message.contains('CANONICAL_CHAPTER_NOT_FOUND')) {
        throw ReaderRuntimeException(
          'LOCAL_COMIC_NOT_FOUND',
          'Local comic was not found for ReaderNext request',
        );
      }
      if (message.contains('CANONICAL_PAGE_ORDER_NOT_FOUND')) {
        throw ReaderRuntimeException(
          'LOCAL_PAGES_EMPTY',
          'Local chapter has no readable pages',
        );
      }
      rethrow;
    }
  }

  Future<List<String>> _loadCanonicalLocalPagesFromStore(
    String localComicId,
    String? chapterId,
  ) async {
    final store = App.repositories.comicDetailStore;
    final snapshot = await store.loadComicSnapshot(localComicId);
    if (snapshot == null || snapshot.localLibraryItems.isEmpty) {
      throw StateError('CANONICAL_LOCAL_COMIC_NOT_FOUND:$localComicId');
    }

    final targetChapterId =
        chapterId ??
        (snapshot.chapters.isNotEmpty
            ? snapshot.chapters.first.id
            : '$localComicId:__imported__');
    final pages = await store.loadActivePageOrderPages(targetChapterId);
    if (pages.isEmpty) {
      throw StateError('CANONICAL_PAGE_ORDER_NOT_FOUND:$targetChapterId');
    }

    return pages.map((page) => Uri.file(page.localPath).toString()).toList();
  }
}
