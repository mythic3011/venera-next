import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/utils/io.dart';

typedef LogFilePathResolver = String? Function();

class LogRetentionPolicy {
  const LogRetentionPolicy({
    required this.maxCurrentBytes,
    required this.maxArchives,
    this.compressArchives = false,
  });

  final int maxCurrentBytes;
  final int maxArchives;
  final bool compressArchives;
}

class LogStorageWriter {
  LogStorageWriter({
    LogFilePathResolver? pathResolver,
    LogRetentionPolicy? retentionPolicy,
  }) : _pathResolver = pathResolver ?? _defaultPathResolver,
       _retentionPolicy = retentionPolicy;

  final LogFilePathResolver _pathResolver;
  final LogRetentionPolicy? _retentionPolicy;

  Future<void> _pending = Future.value();
  IOSink? _sink;
  String? _activePath;

  static String? _defaultPathResolver() {
    if (!App.isInitialized) {
      return null;
    }
    return FilePath.join(App.dataPath, 'logs', 'diagnostics.ndjson');
  }

  Future<void> appendJson(Map<String, Object?> event) {
    return appendLine(jsonEncode(event));
  }

  Future<void> appendLine(String line) {
    _pending = _pending
        .then((_) async {
          final path = _pathResolver();
          if (path == null || path.isEmpty) {
            return;
          }
          await _rotateIfNeeded(path);
          await _ensureSink(path);
          _sink?.writeln(line);
          await _sink?.flush();
        })
        .catchError((Object _, StackTrace __) {
          // Keep diagnostics write failures isolated from app flows.
        });
    return _pending;
  }

  Future<void> _ensureSink(String path) async {
    if (_activePath == path && _sink != null) {
      return;
    }
    await _sink?.flush();
    await _sink?.close();
    final file = File(path);
    await file.parent.create(recursive: true);
    _sink = file.openWrite(mode: FileMode.append);
    _activePath = path;
  }

  Future<void> _rotateIfNeeded(String path) async {
    final policy = _retentionPolicy;
    if (policy == null || policy.maxCurrentBytes <= 0) {
      return;
    }
    final currentFile = File(path);
    if (!await currentFile.exists()) {
      return;
    }
    final length = await currentFile.length();
    if (length <= policy.maxCurrentBytes) {
      return;
    }

    final lock = await _acquireRotationLock(path);
    try {
      final recheckFile = File(path);
      if (!await recheckFile.exists()) {
        return;
      }
      final recheckedLength = await recheckFile.length();
      if (recheckedLength <= policy.maxCurrentBytes) {
        return;
      }

      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      _activePath = null;

      final archivePath = '$path.${_archiveTimestamp()}';
      await recheckFile.rename(archivePath);
      if (policy.compressArchives) {
        await _compressArchive(archivePath);
      }
      await _trimArchives(path, policy.maxArchives);
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }

  Future<RandomAccessFile> _acquireRotationLock(String path) async {
    final lockFile = File(FilePath.join(File(path).parent.path, 'log.lock'));
    await lockFile.parent.create(recursive: true);
    final raf = await lockFile.open(mode: FileMode.write);
    await raf.lock(FileLock.blockingExclusive);
    return raf;
  }

  static String _archiveTimestamp() {
    final now = DateTime.now().toUtc().toIso8601String();
    return now
        .replaceAll('-', '')
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('T', 'T')
        .replaceAll('Z', 'Z');
  }

  Future<void> _trimArchives(String path, int maxArchives) async {
    if (maxArchives < 0) {
      return;
    }
    final entities = await File(path).parent.list().toList();
    final archives = entities
        .whereType<File>()
        .where((entry) => entry.path.startsWith('$path.'))
        .toList(growable: false);
    archives.sort((a, b) {
      final aName = a.uri.pathSegments.last;
      final bName = b.uri.pathSegments.last;
      return bName.compareTo(aName);
    });
    for (var i = maxArchives; i < archives.length; i++) {
      await archives[i].delete();
    }
  }

  Future<void> _compressArchive(String archivePath) async {
    final source = File(archivePath);
    if (!await source.exists()) {
      return;
    }
    final bytes = await source.readAsBytes();
    final compressed = gzip.encode(bytes);
    final gzPath = '$archivePath.gz';
    await File(gzPath).writeAsBytes(compressed, flush: true);
    await source.delete();
  }

  Future<void> close() async {
    await _pending;
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _activePath = null;
  }

  @visibleForTesting
  Future<void> closeForTesting() {
    return close();
  }
}
