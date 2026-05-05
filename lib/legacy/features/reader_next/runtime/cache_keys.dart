import 'models.dart';

String buildReaderImageCacheKey({
  required SourceRef sourceRef,
  required String canonicalComicId,
  required String upstreamComicRefId,
  required String chapterRefId,
  required String imageKey,
}) {
  if (!sourceRef.isRemote) {
    throw ReaderRuntimeException(
      'SOURCE_REF_REQUIRED',
      'Remote image cache key requires remote SourceRef',
    );
  }
  if (sourceRef.sourceKey.isEmpty ||
      canonicalComicId.isEmpty ||
      upstreamComicRefId.isEmpty ||
      chapterRefId.isEmpty ||
      imageKey.isEmpty) {
    throw ReaderRuntimeException(
      'CACHE_KEY_INVALID',
      'All cache key segments must be non-empty',
    );
  }
  if (upstreamComicRefId.contains(':')) {
    throw ReaderRuntimeException(
      'CACHE_KEY_INVALID',
      'upstreamComicRefId must not be canonical',
    );
  }
  return [
    sourceRef.sourceKey,
    canonicalComicId,
    upstreamComicRefId,
    chapterRefId,
    imageKey,
  ].join('@');
}
