import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/log_diagnostics.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';

class DebugDiagnosticsService {
  const DebugDiagnosticsService();

  Future<Map<String, Object?>> healthPayload({
    required bool serverRunning,
    required String platform,
  }) async {
    final snapshot = await LogDiagnostics.diagnosticSnapshot(limit: 1);
    return {
      'ok': true,
      'platform': platform,
      'logCount': snapshot.sessionTotalCount,
      'sessionLogCount': snapshot.sessionTotalCount,
      'persistedLogCount': snapshot.persistedTotalCount,
      'debugServer': {'running': serverRunning},
    };
  }

  Future<Map<String, Object?>> logsPayload({
    required String level,
    required int limit,
  }) async {
    final snapshot = await LogDiagnostics.diagnosticSnapshot(
      level: level,
      limit: limit,
    );
    return {
      'logs': snapshot.logs,
      'count': snapshot.logs.length,
      'limit': limit,
      'sources': {
        'session': snapshot.sessionTotalCount,
        'persisted': snapshot.persistedTotalCount,
      },
    };
  }

  Future<Map<String, Object?>> diagnosticsPayload({
    required bool serverRunning,
    required String? baseUrl,
    required String platform,
  }) async {
    final errorSnapshot = await LogDiagnostics.diagnosticSnapshot(
      level: 'error',
      limit: 20,
    );
    return {
      'platform': {'os': platform, 'isDesktop': App.isDesktop},
      'runtime': {'appVersion': App.version},
      'debugServer': {'running': serverRunning, 'baseUrl': baseUrl},
      'paths': {
        'dataPath': App.isInitialized ? App.dataPath : null,
        'cachePath': App.isInitialized ? App.cachePath : null,
        'logFilePath': Log.logFilePath,
      },
      'logs': {
        'totalCount': errorSnapshot.totalCount,
        'sessionTotalCount': errorSnapshot.sessionTotalCount,
        'persistedTotalCount': errorSnapshot.persistedTotalCount,
        'recentErrorCount': errorSnapshot.sessionErrorCount,
        'persistedErrorCount': errorSnapshot.persistedErrorCount,
        'newestErrors': errorSnapshot.logs,
      },
      ...ReaderDiagnostics.toDiagnosticsJson(),
    };
  }
}
