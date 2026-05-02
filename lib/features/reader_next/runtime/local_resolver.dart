import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/foundation/source_identity/constants.dart';
import 'package:venera/utils/io.dart';

import 'models.dart';
import 'ports.dart';

class LegacyLocalReaderPageResolver implements LocalReaderPageResolver {
  const LegacyLocalReaderPageResolver({
    Future<void> Function()? ensureInitialized,
    dynamic Function(String comicId, String sourceKey)? findComicBySourceKey,
    Future<List<String>> Function(
      String comicId,
      String sourceKey,
      Object chapterOrIndex,
    )?
    loadImagesBySourceKey,
  }) : _ensureInitialized = ensureInitialized,
       _findComicBySourceKey = findComicBySourceKey,
       _loadImagesBySourceKey = loadImagesBySourceKey;

  final Future<void> Function()? _ensureInitialized;
  final dynamic Function(String comicId, String sourceKey)?
  _findComicBySourceKey;
  final Future<List<String>> Function(
    String comicId,
    String sourceKey,
    Object chapterOrIndex,
  )?
  _loadImagesBySourceKey;

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

    try {
      await (_ensureInitialized ?? legacyEnsureLocalComicsInitialized).call();
    } catch (_) {
      recordBlocked('LOCAL_STORAGE_UNAVAILABLE');
      throw ReaderRuntimeException(
        'LOCAL_STORAGE_UNAVAILABLE',
        'Local storage is unavailable',
      );
    }

    final comic = _safeFindLocalComic(
      comicId: sourceRef.upstreamComicRefId,
      sourceKey: sourceRef.sourceKey,
    );
    if (comic == null) {
      recordBlocked('LOCAL_COMIC_NOT_FOUND');
      throw ReaderRuntimeException(
        'LOCAL_COMIC_NOT_FOUND',
        'Local comic was not found for ReaderNext request',
      );
    }

    if (comic.hasChapters &&
        (comic.chapters == null ||
            !comic.chapters!.allChapters.containsKey(chapterRefId))) {
      recordBlocked('LOCAL_CHAPTER_NOT_FOUND');
      throw ReaderRuntimeException(
        'LOCAL_CHAPTER_NOT_FOUND',
        'Local chapter was not found for ReaderNext request',
      );
    }

    final paths = await _safeLoadLocalComicImages(
      comicId: sourceRef.upstreamComicRefId,
      sourceKey: sourceRef.sourceKey,
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

  dynamic _safeFindLocalComic({
    required String comicId,
    required String sourceKey,
  }) {
    try {
      return (_findComicBySourceKey ?? legacyFindLocalComicBySourceKey).call(
        comicId,
        sourceKey,
      );
    } catch (error) {
      if (_isLegacyUnavailable(error)) {
        throw ReaderRuntimeException(
          'LOCAL_STORAGE_UNAVAILABLE',
          'Local storage is unavailable',
        );
      }
      rethrow;
    }
  }

  Future<List<String>> _safeLoadLocalComicImages({
    required String comicId,
    required String sourceKey,
    required String chapterRefId,
  }) async {
    try {
      return await (_loadImagesBySourceKey ??
              legacyLoadLocalComicImagesBySourceKey)
          .call(comicId, sourceKey, chapterRefId);
    } catch (error) {
      if (_isLegacyUnavailable(error)) {
        throw ReaderRuntimeException(
          'LOCAL_STORAGE_UNAVAILABLE',
          'Local storage is unavailable',
        );
      }
      rethrow;
    }
  }

  bool _isLegacyUnavailable(Object error) {
    final text = error.toString();
    return text.contains('LateInitializationError') ||
        text.contains('late initialization');
  }
}
