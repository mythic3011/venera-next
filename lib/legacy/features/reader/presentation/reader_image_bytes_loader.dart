part of 'reader.dart';

Future<Uint8List> _readReaderImageBytes({
  required String imageKey,
  String? sourceKey,
  String? canonicalComicId,
  String? upstreamComicRefId,
  String? chapterRefId,
  Future<File?> Function(String cacheKey)? findCache,
  // Compatibility aliases for older callsites.
  String? comicId,
  String? chapterId,
}) async {
  final resolvedSourceKey = sourceKey ?? localSourceKey;
  final resolvedCanonicalComicRefId = canonicalComicId ?? comicId;
  final resolvedChapterRefId = chapterRefId ?? chapterId;
  final resolvedUpstreamComicRefId =
      upstreamComicRefId ?? resolvedCanonicalComicRefId;
  if (resolvedCanonicalComicRefId == null ||
      resolvedCanonicalComicRefId.isEmpty) {
    throw StateError('IMAGE_IDENTITY_MISSING: canonicalComicRefId');
  }
  if (resolvedChapterRefId == null || resolvedChapterRefId.isEmpty) {
    throw StateError('IMAGE_IDENTITY_MISSING: chapterRefId');
  }
  if (imageKey.startsWith('file://')) {
    final file = File(Uri.parse(imageKey).toFilePath());
    try {
      return await file.readAsBytes();
    } catch (_) {
      recordReaderProviderFailedDiagnostic(
        code: 'LOCAL_IMAGE_READ_FAILED',
        loadMode: 'local',
        sourceKey: resolvedSourceKey,
        canonicalComicId: resolvedCanonicalComicRefId,
        chapterRefId: resolvedChapterRefId,
        imageKey: imageKey,
        fileName: file.name,
      );
      recordReaderRenderBlockedDiagnostic(
        code: 'LOCAL_IMAGE_READ_FAILED',
        loadMode: 'local',
        sourceKey: resolvedSourceKey,
        canonicalComicId: resolvedCanonicalComicRefId,
        chapterRefId: resolvedChapterRefId,
        imageKey: imageKey,
        fileName: file.name,
      );
      rethrow;
    }
  }
  final cacheKey =
      '$imageKey@$resolvedSourceKey@$resolvedCanonicalComicRefId@$resolvedUpstreamComicRefId@$resolvedChapterRefId';
  final cache = await (findCache ?? CacheManager().findCache).call(cacheKey);
  if (cache == null) {
    recordReaderProviderFailedDiagnostic(
      code: 'IMAGE_CACHE_MISS',
      loadMode: 'remote',
      sourceKey: resolvedSourceKey,
      canonicalComicId: resolvedCanonicalComicRefId,
      upstreamComicRefId: resolvedUpstreamComicRefId,
      chapterRefId: resolvedChapterRefId,
      imageKey: imageKey,
    );
    recordReaderRenderBlockedDiagnostic(
      code: 'IMAGE_CACHE_MISS',
      loadMode: 'remote',
      sourceKey: resolvedSourceKey,
      canonicalComicId: resolvedCanonicalComicRefId,
      upstreamComicRefId: resolvedUpstreamComicRefId,
      chapterRefId: resolvedChapterRefId,
      imageKey: imageKey,
    );
    throw StateError(
      'IMAGE_CACHE_MISS: imageKey=$imageKey sourceKey=$resolvedSourceKey canonicalComicRefId=$resolvedCanonicalComicRefId upstreamComicRefId=$resolvedUpstreamComicRefId chapterRefId=$resolvedChapterRefId',
    );
  }
  return cache.readAsBytes();
}

@visibleForTesting
Future<Uint8List> readReaderImageBytesForTesting({
  required String imageKey,
  required String sourceKey,
  required String canonicalComicId,
  required String upstreamComicRefId,
  required String chapterRefId,
  Future<File?> Function(String cacheKey)? findCache,
}) {
  return _readReaderImageBytes(
    imageKey: imageKey,
    sourceKey: sourceKey,
    canonicalComicId: canonicalComicId,
    upstreamComicRefId: upstreamComicRefId,
    chapterRefId: chapterRefId,
    findCache: findCache,
  );
}
