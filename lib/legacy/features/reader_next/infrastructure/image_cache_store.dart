import 'dart:io';

import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:venera/features/reader_next/runtime/ports.dart';
import 'package:venera/foundation/cache_manager.dart';

typedef FindCacheFn = Future<File?> Function(String key);
typedef WriteCacheFn = Future<void> Function(String key, List<int> bytes);

class CacheManagerImageCacheStore implements ImageCacheStore {
  CacheManagerImageCacheStore({
    this.cacheKeyPrefix = 'reader-next:image',
    FindCacheFn? findCache,
    WriteCacheFn? writeCache,
  }) : _findCache = findCache ?? CacheManager().findCache,
       _writeCache = writeCache ?? CacheManager().writeCache;

  final String cacheKeyPrefix;
  final FindCacheFn _findCache;
  final WriteCacheFn _writeCache;

  @override
  Future<List<int>?> read({required String cacheKey}) async {
    _assertRuntimeCacheKey(cacheKey);
    final file = await _findCache(_toStorageKey(cacheKey));
    if (file == null) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> write({
    required String cacheKey,
    required List<int> bytes,
  }) async {
    _assertRuntimeCacheKey(cacheKey);
    await _writeCache(_toStorageKey(cacheKey), bytes);
  }

  String _toStorageKey(String runtimeCacheKey) {
    return '$cacheKeyPrefix@$runtimeCacheKey';
  }

  void _assertRuntimeCacheKey(String key) {
    if (key.trim().isEmpty) {
      throw ReaderRuntimeException(
        'CACHE_KEY_INVALID',
        'cache key must be non-empty',
      );
    }
    final segments = key.split('@');
    if (segments.length != 5 || segments.any((segment) => segment.isEmpty)) {
      throw ReaderRuntimeException(
        'CACHE_KEY_INVALID',
        'cache key must include sourceKey, canonicalComicId, upstreamComicRefId, chapterRefId, imageKey',
      );
    }
  }
}
