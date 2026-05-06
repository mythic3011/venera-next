import 'dart:async';

import 'package:venera/foundation/database/app_db_helper.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

typedef CanonicalDbWriteCallback<T> = Future<T> Function();

class CanonicalDbWriteGate {
  CanonicalDbWriteGate._();

  static int _pendingWrites = 0;

  static int get pendingWrites => _pendingWrites;

  static Future<T> run<T>({
    required String dbPath,
    required String domain,
    required String operation,
    required CanonicalDbWriteCallback<T> callback,
  }) async {
    _pendingWrites++;
    try {
      return await AppDbHelper.instance.write(
        '$domain.$operation',
        callback,
      );
    } catch (error) {
      final sqliteCode = extractSqliteCode(error);
      if (sqliteCode == 5 || sqliteCode == 517) {
        AppDiagnostics.warn(
          'db.write',
          'db.write.locked',
          data: {
            'domain': domain,
            'operation': operation,
            'sqliteCode': sqliteCode,
            'errorType': error.runtimeType.toString(),
          },
        );
      }
      rethrow;
    } finally {
      _pendingWrites--;
    }
  }

  static int? extractSqliteCode(Object error) {
    return AppDbHelper.instance.classifyBusyError(error).sqliteCode;
  }
}
