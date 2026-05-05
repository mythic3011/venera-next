import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/diagnostics/log_diagnostics.dart';
import 'package:venera/foundation/reader/reader_debug_snapshot.dart';
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
    final minLevel = _diagnosticLevelFromLogFilter(level);
    final structured = DevDiagnosticsApi.recent(
      minLevel: minLevel,
    ).map((event) => event.toJson()).toList(growable: false);
    return {
      'logs': snapshot.logs,
      'structuredLogs': structured,
      'count': snapshot.logs.length,
      'structuredCount': structured.length,
      'limit': limit,
      'sources': {
        'session': snapshot.sessionTotalCount,
        'persisted': snapshot.persistedTotalCount,
        'structured': structured.length,
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
    final structuredEvents = DevDiagnosticsApi.recent();
    final newestWarningsAndErrors = DevDiagnosticsApi.recent(
      minLevel: DiagnosticLevel.warn,
    ).reversed.take(20).map((event) => event.toJson()).toList(growable: false);
    final readerDiagnostics = ReaderDiagnostics.toDiagnosticsJson();
    final readerDebugSnapshot = await _readerDebugSnapshotPayload(
      readerDiagnostics,
    );
    final sessionNewestErrors = errorSnapshot.logs
        .where((entry) => entry['source'] == 'session')
        .toList(growable: false);
    final persistedNewestErrors = errorSnapshot.logs
        .where((entry) => entry['source'] == 'persisted')
        .toList(growable: false);
    final structuredNewestErrors =
        DevDiagnosticsApi.recent(minLevel: DiagnosticLevel.error).reversed
            .take(20)
            .map((event) {
              final json = event.toJson();
              return <String, Object?>{...json, 'source': 'structured'};
            })
            .toList(growable: false);
    return {
      'platform': {'os': platform, 'isDesktop': App.isDesktop},
      'runtime': {
        'appVersion': App.version,
        'runtimeRoot': App.isInitialized ? App.dataPath : null,
        'runtimeRootBase': App.runtimeRootBasePath,
        'runtimeRootOverrideActive': App.runtimeRootOverrideActive,
        'runtimeRootOverridePath': App.runtimeRootOverridePath,
      },
      'debugServer': {'running': serverRunning, 'baseUrl': baseUrl},
      'structuredDiagnostics': {
        'enabled': DevDiagnosticsApi.isEnabled,
        'eventCount': structuredEvents.length,
        'runtimeLevel': AppDiagnostics.runtimeLevel.name,
        'persistedLevel': AppDiagnostics.persistedLevel.name,
        'channels': structuredEvents
            .map((event) => event.channel)
            .toSet()
            .toList(growable: false),
        'newestWarningsAndErrors': newestWarningsAndErrors,
        'ndjsonLineCount': DevDiagnosticsApi.exportNdjson().isEmpty
            ? 0
            : DevDiagnosticsApi.exportNdjson().split('\n').length,
      },
      'paths': {
        'runtimeRoot': App.isInitialized ? App.dataPath : null,
        'runtimeRootBase': App.runtimeRootBasePath,
        'runtimeRootOverrideActive': App.runtimeRootOverrideActive,
        'runtimeRootOverridePath': App.runtimeRootOverridePath,
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
        'newestErrorsSourceHint':
            'Use logs.groupedIssues as the deduped primary view; newestErrors/newestErrorsBySource are compatibility drill-down buckets.',
        'groupedIssues': errorSnapshot.groupedIssues,
        'newestErrors': errorSnapshot.logs,
        'newestErrorsBySource': {
          'session': sessionNewestErrors,
          'persisted': persistedNewestErrors,
          'structured': structuredNewestErrors,
        },
      },
      ...readerDiagnostics,
      if (readerDebugSnapshot != null)
        'readerDebugSnapshot': readerDebugSnapshot,
    };
  }

  Future<Map<String, Object?>?> _readerDebugSnapshotPayload(
    Map<String, dynamic> readerDiagnostics,
  ) async {
    if (!App.isInitialized) {
      return null;
    }
    final trace = readerDiagnostics['readerTrace'];
    if (trace is! Map<String, dynamic>) {
      return null;
    }
    final currentReader = trace['currentReader'];
    if (currentReader is! Map<String, dynamic>) {
      return null;
    }
    final comicId = currentReader['comicId'];
    final loadMode = currentReader['loadMode'];
    if (comicId is! String || comicId.isEmpty) {
      return null;
    }
    if (loadMode is! String || loadMode.isEmpty) {
      return null;
    }
    final chapterId = currentReader['chapterId'];
    final lifecycle = currentReader['lifecycle'];
    try {
      final snapshot =
          await ReaderDebugSnapshotService(
            localLibraryStore: App.repositories.localLibrary.store,
            comicDetailStore: App.repositories.comicDetailStore,
            readerSessionStore: App.repositories.readerSession.store,
          ).build(
            comicId: comicId,
            chapterId: chapterId is String && chapterId.isNotEmpty
                ? chapterId
                : null,
            loadMode: loadMode,
            controllerLifecycle: lifecycle is String && lifecycle.isNotEmpty
                ? lifecycle
                : 'unknown',
          );
      return snapshot.toJson();
    } catch (error) {
      return {
        'error': error.toString(),
        'comicId': comicId,
        if (chapterId is String && chapterId.isNotEmpty) 'chapterId': chapterId,
        'loadMode': loadMode,
      };
    }
  }

  DiagnosticLevel? _diagnosticLevelFromLogFilter(String level) {
    return switch (level.toLowerCase()) {
      'info' => DiagnosticLevel.info,
      'warning' => DiagnosticLevel.warn,
      'warn' => DiagnosticLevel.warn,
      'error' => DiagnosticLevel.error,
      _ => null,
    };
  }
}
