import 'dart:async';

import 'package:venera/foundation/diagnostics/diagnostics.dart';

typedef CanonicalDbWriteCallback<T> = Future<T> Function();

class CanonicalDbWriteGate {
  CanonicalDbWriteGate._();

  static const int _maxAttempts = 3;
  static final Map<String, Future<void>> _tailsByDbPath = {};
  static final Object _zoneKey = Object();
  static int _pendingWrites = 0;

  static int get pendingWrites => _pendingWrites;

  static Future<T> run<T>({
    required String dbPath,
    required String domain,
    required String operation,
    required CanonicalDbWriteCallback<T> callback,
  }) async {
    if (Zone.current[_zoneKey] == dbPath) {
      _pendingWrites++;
      try {
        return await _runWithRetry(
          domain: domain,
          operation: operation,
          callback: callback,
        );
      } finally {
        _pendingWrites--;
      }
    }

    final tail = _tailsByDbPath[dbPath] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> nextTail;
    nextTail = tail.whenComplete(() async {
      try {
        _pendingWrites++;
        final result = await runZoned(
          () => _runWithRetry(
            domain: domain,
            operation: operation,
            callback: callback,
          ),
          zoneValues: {_zoneKey: dbPath},
        );
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _pendingWrites--;
      }
    });
    late final Future<void> wrappedTail;
    wrappedTail = nextTail.whenComplete(() {
      if (identical(_tailsByDbPath[dbPath], wrappedTail)) {
        _tailsByDbPath.remove(dbPath);
      }
    });
    _tailsByDbPath[dbPath] = wrappedTail;
    return completer.future;
  }

  static Future<T> _runWithRetry<T>({
    required String domain,
    required String operation,
    required CanonicalDbWriteCallback<T> callback,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await callback();
      } catch (error) {
        final sqliteCode = extractSqliteCode(error);
        final retryable = sqliteCode == 5 || sqliteCode == 517;
        attempt += 1;
        if (!retryable || attempt >= _maxAttempts) {
          if (retryable) {
            AppDiagnostics.warn(
              'db.write',
              'db.write.locked',
              data: {
                'domain': domain,
                'operation': operation,
                'attemptCount': attempt,
                'sqliteCode': sqliteCode,
                'errorType': error.runtimeType.toString(),
              },
            );
          }
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 8 * attempt));
      }
    }
  }

  static int? extractSqliteCode(Object error) {
    try {
      final dynamic raw = error;
      final int? extended = raw.extendedResultCode as int?;
      if (extended != null) return extended;
      final int? result = raw.resultCode as int?;
      if (result != null) return result;
    } catch (_) {}
    final message = error.toString().toLowerCase();
    if (message.contains('sqlite_locked_sharedcache')) return 517;
    if (message.contains('sqlite_locked') || message.contains('sqlite_busy')) {
      return 5;
    }
    if (message.contains('database is locked')) return 5;
    return null;
  }
}
