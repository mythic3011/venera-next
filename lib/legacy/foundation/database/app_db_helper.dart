import 'dart:async';

import 'package:drift/drift.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

class AppDbHelper {
  AppDbHelper._();
  static final AppDbHelper instance = AppDbHelper._();

  static const int _maxAttempts = 3;
  static Future<void> _writeTail = Future<void>.value();
  static int _pendingWrites = 0;
  static final Object _writeZoneKey = Object();

  static int get pendingWrites => _pendingWrites;

  Future<T> read<T>(String label, Future<T> Function() action) {
    return action();
  }

  Future<T> write<T>(String label, Future<T> Function() action) {
    if (Zone.current[_writeZoneKey] == true) {
      return _runWithRetry(label: label, action: action);
    }
    final completer = Completer<T>();
    _writeTail = _writeTail
        .catchError((_) {})
        .then((_) async {
          final startedAt = DateTime.now();
          _pendingWrites += 1;
          AppDiagnostics.trace(
            'db.write',
            'db.write.start',
            data: {'label': label, 'pendingWrites': _pendingWrites},
          );
          try {
            final result = await runZoned(
              () => _runWithRetry(label: label, action: action),
              zoneValues: {_writeZoneKey: true},
            );
            final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
            AppDiagnostics.trace(
              'db.write',
              'db.write.end',
              data: {
                'label': label,
                'pendingWrites': _pendingWrites,
                'elapsedMs': elapsedMs,
              },
            );
            completer.complete(result);
          } catch (error, stackTrace) {
            final classification = classifyBusyError(error);
            AppDiagnostics.warn(
              'db.write',
              'db.write.failed',
              data: {
                'label': label,
                'pendingWrites': _pendingWrites,
                'errorType': error.runtimeType.toString(),
                'isLockedOrBusy': classification.isLockedOrBusy,
                'sqliteCode': classification.sqliteCode,
              },
            );
            completer.completeError(error, stackTrace);
          } finally {
            _pendingWrites -= 1;
          }
        });

    return completer.future;
  }

  Future<T> transaction<T>(
    String label,
    GeneratedDatabase db,
    Future<T> Function() action,
  ) {
    return write(label, () => db.transaction(action));
  }

  Future<void> customWrite(
    String label,
    GeneratedDatabase db,
    String sql,
    List<Object?> args,
  ) {
    return write(label, () => db.customStatement(sql, args));
  }

  Future<T> _runWithRetry<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await action();
      } catch (error) {
        final classification = classifyBusyError(error);
        if (!classification.isLockedOrBusy || attempt >= _maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 8 * attempt));
        AppDiagnostics.trace(
          'db.write',
          'db.write.retry',
          data: {
            'label': label,
            'attempt': attempt,
            'sqliteCode': classification.sqliteCode,
          },
        );
      }
    }
  }

  DbBusyClassification classifyBusyError(Object error) {
    int? sqliteCode;
    try {
      final dynamic raw = error;
      sqliteCode = raw.extendedResultCode as int? ?? raw.resultCode as int?;
    } catch (_) {
      sqliteCode = null;
    }

    final message = error.toString().toLowerCase();
    final messageLocked = message.contains('database is locked') ||
        message.contains('sqlite_busy') ||
        message.contains('sqlite_locked') ||
        message.contains('busy');
    final codeLocked = sqliteCode == 5 || sqliteCode == 517;

    return DbBusyClassification(
      isLockedOrBusy: codeLocked || messageLocked,
      sqliteCode: sqliteCode,
    );
  }

}

class DbBusyClassification {
  const DbBusyClassification({
    required this.isLockedOrBusy,
    required this.sqliteCode,
  });

  final bool isLockedOrBusy;
  final int? sqliteCode;
}
