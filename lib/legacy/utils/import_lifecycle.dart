import 'dart:async';
import 'dart:convert';

import 'package:venera/foundation/diagnostics/diagnostics.dart';

const _importLifecycleZoneKey = #veneraImportLifecycleTrace;

class ImportLifecycleTrace {
  ImportLifecycleTrace._({
    required this.id,
    required this.operation,
    required this.baseData,
  }) : _watch = Stopwatch()..start();

  final String id;
  final String operation;
  final Map<String, Object?> baseData;
  final Stopwatch _watch;

  static ImportLifecycleTrace? get current {
    final value = Zone.current[_importLifecycleZoneKey];
    return value is ImportLifecycleTrace ? value : null;
  }

  static ImportLifecycleTrace start({
    required String operation,
    String? sourceName,
    String? sourceType,
    Map<String, Object?> data = const {},
  }) {
    final trace = ImportLifecycleTrace._(
      id: 'import-${DateTime.now().microsecondsSinceEpoch}',
      operation: operation,
      baseData: _sanitizeData(<String, Object?>{
        'operation': operation,
        if (sourceName != null) 'sourceName': sourceName,
        if (sourceType != null) 'sourceType': sourceType,
        ...data,
      }),
    );
    trace.info('import.lifecycle.started');
    return trace;
  }

  Future<T> run<T>(Future<T> Function() action) {
    return runZoned(action, zoneValues: {_importLifecycleZoneKey: this});
  }

  void phase(String phase, {Map<String, Object?> data = const {}}) {
    AppDiagnostics.trace(
      'import.lifecycle',
      'import.lifecycle.phase',
      data: _eventData(<String, Object?>{'phase': phase, ...data}),
    );
  }

  void info(String message, {Map<String, Object?> data = const {}}) {
    AppDiagnostics.info('import.lifecycle', message, data: _eventData(data));
  }

  void completed({Map<String, Object?> data = const {}}) {
    _watch.stop();
    AppDiagnostics.info(
      'import.lifecycle',
      'import.lifecycle.completed',
      data: _eventData(data),
    );
  }

  void failed(
    Object error, {
    StackTrace? stackTrace,
    String? phase,
    Map<String, Object?> data = const {},
  }) {
    _watch.stop();
    AppDiagnostics.error(
      'import.lifecycle',
      error,
      stackTrace: stackTrace,
      message: 'import.lifecycle.failed',
      data: _eventData(<String, Object?>{
        if (phase != null) 'phase': phase,
        'errorType': error.runtimeType.toString(),
        ...data,
      }),
    );
  }

  Map<String, Object?> _eventData(Map<String, Object?> data) {
    return _sanitizeData(<String, Object?>{
      'importId': id,
      ...baseData,
      'elapsedMs': _watch.elapsedMilliseconds,
      ...data,
    });
  }

  static Map<String, Object?> _sanitizeData(Map<String, Object?> raw) {
    final result = <String, Object?>{};
    raw.forEach((key, value) {
      if (value == null) {
        result[key] = null;
        return;
      }
      if (value is Map<String, Object?>) {
        result[key] = _sanitizeData(value);
        return;
      }
      if (value is List) {
        result[key] = value.map(_sanitizeValue).toList(growable: false);
        return;
      }
      if (_isPathLikeKey(key)) {
        result.remove(key);
        if (value is List) {
          final hashes = <String>[];
          final names = <String>[];
          final aliases = <String>[];
          for (final entry in value) {
            final text = entry.toString();
            hashes.add(_hashPath(text));
            names.add(_pathName(text));
            aliases.add(_rootAlias(text));
          }
          result['${key}Hashes'] = hashes;
          result['${key}Names'] = names;
          result['${key}RootAliases'] = aliases;
          return;
        }
        final text = value.toString();
        result['${key}Hash'] = _hashPath(text);
        result['${key}Name'] = _pathName(text);
        result['${key}RootAlias'] = _rootAlias(text);
        return;
      }
      result[key] = _sanitizeValue(value);
    });
    return result;
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Map<String, Object?>) {
      return _sanitizeData(value);
    }
    if (value is List) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    return value;
  }

  static bool _isPathLikeKey(String key) {
    if (key.endsWith('Hash') ||
        key.endsWith('Hashes') ||
        key.endsWith('Name') ||
        key.endsWith('Names') ||
        key.endsWith('RootAlias') ||
        key.endsWith('RootAliases')) {
      return false;
    }
    const pathKeys = {
      'sourcePath',
      'cachePath',
      'rootPath',
      'targetDirectory',
      'destinationRoot',
      'sourcePaths',
    };
    if (pathKeys.contains(key)) {
      return true;
    }
    final lower = key.toLowerCase();
    return lower.contains('path') || lower.contains('directory');
  }

  static String _pathName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i].trim();
      if (part.isNotEmpty) {
        return part;
      }
    }
    return '';
  }

  static String _rootAlias(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    if (normalized.contains('/cache') || normalized.contains('/tmp')) {
      return '<CACHE>';
    }
    if (normalized.contains('/app') && normalized.contains('/data')) {
      return '<APP_DATA>';
    }
    return '<IMPORT_ROOT>';
  }

  static String _hashPath(String value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
