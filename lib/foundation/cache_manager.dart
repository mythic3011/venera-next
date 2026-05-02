import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/utils/io.dart';

import 'app.dart';

class CacheManager {
  static String get cachePath => '${App.cachePath}/cache';
  static const String _defaultCacheNamespace = 'other';
  static const Set<String> _allowedNamespaces = <String>{
    'cover_image',
    'reader_page_image',
    'thumbnail',
    'source_asset',
    'other',
  };

  static CacheManager? instance;

  int? _currentSize;

  /// size in bytes
  int get currentSize => _currentSize ?? 0;

  int _dirBucket = 0;

  int _limitSize = 2 * 1024 * 1024 * 1024;

  bool _isChecking = false;

  CacheManager._create() {
    Directory(cachePath).createSync(recursive: true);
    // M25.1: legacy cache.db sidecar is disposable and non-authoritative.
    _scanCacheDirSize().then((value) {
      _currentSize = value;
      checkCache();
    });
  }

  factory CacheManager() => instance ??= CacheManager._create();

  UnifiedComicsStore get _store => App.unifiedComicsStore;

  Future<int> _scanCacheDirSize() async {
    final rootPath = cachePath;
    final result = await Isolate.run(() async {
      int totalSize = 0;
      final List<(String, String, int)> managed = <(String, String, int)>[];
      await for (final entity in Directory(rootPath).list(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final size = await entity.length();
        final segments = entity.uri.pathSegments;
        final name = segments.isEmpty ? '' : segments.last;
        final dir = segments.length >= 2 ? segments[segments.length - 2] : '*';
        managed.add((dir, name, size));
        totalSize += size;
      }
      return (totalSize, managed);
    });
    return result.$1;
  }

  /// set cache size limit in MB
  void setLimitSize(int size) {
    _limitSize = size * 1024 * 1024;
  }

  String _cacheKeyFromRawKey(String rawKey) {
    final digest = sha256.convert(utf8.encode(rawKey));
    return digest.toString();
  }

  String _remoteUrlHashFromRawKey(String rawKey) {
    // Legacy compatibility: existing callers pass `url@source@owner`.
    // Hash only the URL portion for redacted URL-derived metadata.
    final delimiterIndex = rawKey.indexOf('@');
    final urlPart = delimiterIndex >= 0 ? rawKey.substring(0, delimiterIndex) : rawKey;
    final digest = sha256.convert(utf8.encode(urlPart));
    return digest.toString();
  }

  String _normalizeNamespace(String rawNamespace) {
    final normalized = rawNamespace.trim();
    if (_allowedNamespaces.contains(normalized)) {
      return normalized;
    }
    return _defaultCacheNamespace;
  }

  void _assertSafeCachePath() {
    final root = Directory(App.cachePath).absolute.path;
    final target = Directory(cachePath).absolute.path;
    final safePrefix = '$root${Platform.pathSeparator}';
    if (!target.startsWith(safePrefix) || target == root) {
      throw StateError('Unsafe cache path: $target');
    }
  }

  Future<void> writeCache(
    String key,
    List<int> data, [
    int duration = 7 * 24 * 60 * 60 * 1000,
    String namespace = _defaultCacheNamespace,
  ]) async {
    final cacheKey = _cacheKeyFromRawKey(key);
    await delete(key);
    _dirBucket = (_dirBucket + 1) % 100;
    final dir = _dirBucket.toString();
    final fileName = sha256.convert(utf8.encode(key)).toString();
    final file = File('$cachePath/$dir/$fileName');
    await file.create(recursive: true);
    await file.writeAsBytes(data);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final expiresAtMs = nowMs + duration;
    try {
      await _store.upsertCacheEntry(
        CacheEntryRecord(
          cacheKey: cacheKey,
          namespace: _normalizeNamespace(namespace),
          sourcePlatformId: null,
          ownerRef: null,
          remoteUrlHash: _remoteUrlHashFromRawKey(key),
          storageDir: dir,
          fileName: fileName,
          expiresAtMs: expiresAtMs,
          contentType: null,
          sizeBytes: data.length,
          createdAtMs: nowMs,
          lastAccessedAtMs: nowMs,
        ),
      );
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
    if (_currentSize != null) {
      _currentSize = _currentSize! + data.length;
    }
    checkCacheIfRequired();
  }

  Future<File?> findCache(String key) async {
    final cacheKey = _cacheKeyFromRawKey(key);
    final entry = await _store.loadCacheEntry(cacheKey);
    if (entry == null) {
      return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final file = File('$cachePath/${entry.storageDir}/${entry.fileName}');
    if (entry.expiresAtMs < now) {
      await _store.deleteCacheEntry(cacheKey);
      if (await file.exists()) {
        await file.delete();
      }
      return null;
    }
    if (await file.exists()) {
      final nextExpiry = now + 7 * 24 * 60 * 60 * 1000;
      await _store.touchCacheEntryAccess(
        cacheKey: cacheKey,
        expiresAtMs: nextExpiry,
        lastAccessedAtMs: now,
      );
      return file;
    }
    await _store.deleteCacheEntry(cacheKey);
    return null;
  }

  void checkCacheIfRequired() {
    if (_currentSize != null && _currentSize! > _limitSize) {
      checkCache();
    }
  }

  Future<void> checkCache() async {
    if (_isChecking) {
      return;
    }
    _isChecking = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final expired = await _store.loadExpiredCacheEntries(nowMs: now);
      for (final entry in expired) {
        final file = File('$cachePath/${entry.storageDir}/${entry.fileName}');
        if (await file.exists()) {
          final size = await file.length();
          await file.delete();
          if (_currentSize != null) {
            _currentSize = (_currentSize! - size).clamp(0, 1 << 62);
          }
        }
        await _store.deleteCacheEntry(entry.cacheKey);
      }

      while (_currentSize != null && _currentSize! > _limitSize) {
        final oldest = await _store.loadCacheEntriesOrderedByExpiry(limit: 10);
        if (oldest.isEmpty) {
          _assertSafeCachePath();
          await Directory(cachePath).delete(recursive: true);
          Directory(cachePath).createSync(recursive: true);
          _currentSize = 0;
          break;
        }
        for (final entry in oldest) {
          final file = File('$cachePath/${entry.storageDir}/${entry.fileName}');
          if (await file.exists()) {
            final size = await file.length();
            await file.delete();
            if (_currentSize != null) {
              _currentSize = (_currentSize! - size).clamp(0, 1 << 62);
            }
          }
          await _store.deleteCacheEntry(entry.cacheKey);
          if (_currentSize != null && _currentSize! <= _limitSize) {
            break;
          }
        }
      }
    } finally {
      _isChecking = false;
    }
  }

  Future<void> delete(String key) async {
    final cacheKey = _cacheKeyFromRawKey(key);
    final entry = await _store.loadCacheEntry(cacheKey);
    if (entry == null) {
      return;
    }
    final file = File('$cachePath/${entry.storageDir}/${entry.fileName}');
    var fileSize = 0;
    if (await file.exists()) {
      fileSize = await file.length();
      await file.delete();
    }
    await _store.deleteCacheEntry(cacheKey);
    if (_currentSize != null) {
      _currentSize = (_currentSize! - fileSize).clamp(0, 1 << 62);
    }
  }

  Future<void> clear() async {
    _assertSafeCachePath();
    await Directory(cachePath).delete(recursive: true);
    Directory(cachePath).createSync(recursive: true);
    await _store.deleteAllCacheEntries();
    _currentSize = 0;
  }
}
