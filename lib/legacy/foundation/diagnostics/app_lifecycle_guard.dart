import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/db/canonical_db_write_gate.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/utils/io.dart';

Map<String, Object?> _sanitizeMarkerForLog(Map<String, Object?> marker) {
  final copy = Map<String, Object?>.from(marker);
  copy.remove('runtimeRoot');
  return copy;
}

class AppLifecycleGuard {
  AppLifecycleGuard._();

  static final AppLifecycleGuard instance = AppLifecycleGuard._();
  static const Duration _defaultHeartbeatInterval = Duration(seconds: 15);
  static const Duration _defaultShutdownTimeout = Duration(seconds: 2);

  Timer? _heartbeatTimer;
  bool _started = false;
  bool _shutdownMarked = false;

  @override
  String toString() => 'AppLifecycleGuard(started=$_started)';

  @visibleForTesting
  Future<void> resetForTesting() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _started = false;
    _shutdownMarked = false;
  }

  String get _markerPath =>
      FilePath.join(App.dataPath, 'runtime', 'lifecycle_marker.json');

  Future<void> start({
    Duration heartbeatInterval = _defaultHeartbeatInterval,
  }) async {
    if (!App.isInitialized || _started) {
      return;
    }
    _started = true;

    final previousMarker = await _readMarker();
    if (previousMarker != null && previousMarker['cleanShutdown'] == null) {
      final fatal = previousMarker['fatal'];
      final suspectedReason = fatal is Map
          ? (fatal['classification']?.toString() ?? 'unknown')
          : 'unknown';
      AppDiagnostics.warn(
        'app.lifecycle',
        'app.lifecycle.previousUncleanExit',
        data: {
          'previousPid': previousMarker['pid'],
          'previousStartedAt': previousMarker['startedAt'],
          'lastHeartbeatAt': previousMarker['lastHeartbeatAt'],
          'appVersion': previousMarker['appVersion'],
          'platform': previousMarker['platform'],
          'suspectedReason': suspectedReason,
        },
      );
    }

    final marker = _newMarker(previousMarker);
    await _writeMarker(marker);
    AppDiagnostics.info(
      'app.lifecycle',
      'app.lifecycle.start',
      data: {
        'pid': marker['pid'],
        'appVersion': marker['appVersion'],
        'platform': marker['platform'],
        'startedAt': marker['startedAt'],
        'runtimeRoot': marker['runtimeRoot'],
        if (previousMarker != null)
          'previousMarkerState': {
            'hadCleanShutdown': previousMarker['cleanShutdown'] != null,
            'hadFatal': previousMarker['fatal'] != null,
            'previousPid': previousMarker['pid'],
          },
      },
    );

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_touchHeartbeat());
    });
  }

  Future<void> shutdownRequested({
    required String reason,
    Duration timeout = _defaultShutdownTimeout,
  }) async {
    if (!App.isInitialized) {
      return;
    }
    final pending = pendingWriteSnapshot();
    AppDiagnostics.info(
      'app.lifecycle',
      'app.lifecycle.shutdownRequested',
      data: {'reason': reason, ...pending},
    );

    final drained = await _waitForPendingWrites(timeout: timeout);
    if (!drained) {
      AppDiagnostics.warn(
        'app.lifecycle',
        'app.lifecycle.shutdownWithPendingWrites',
        data: {
          'pendingDbWrites': CanonicalDbWriteGate.pendingWrites,
          'timeoutMs': timeout.inMilliseconds,
        },
      );
    }
  }

  Future<void> markCleanShutdown({required String reason}) async {
    if (!App.isInitialized || _shutdownMarked) {
      return;
    }
    _shutdownMarked = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final marker = await _readMarker() ?? _newMarker(null);
    marker['cleanShutdown'] = {
      'pid': pid,
      'reason': reason,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeMarker(marker);
    AppDiagnostics.info(
      'app.lifecycle',
      'app.lifecycle.cleanShutdown',
      data: {
        'pid': pid,
        'reason': reason,
        'timestamp': (marker['cleanShutdown'] as Map)['timestamp'],
      },
    );
    await flushDiagnostics();
  }

  Future<void> recordFatal(
    Object error,
    StackTrace? stackTrace, {
    required String phase,
  }) async {
    if (!App.isInitialized) {
      return;
    }
    final classification = classifyFatal(error);
    final marker = await _readMarker() ?? _newMarker(null);
    marker['fatal'] = {
      'classification': classification.kind,
      'sqliteCode': classification.sqliteCode,
      'exceptionType': error.runtimeType.toString(),
      'phase': phase,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeMarker(marker);

    if (classification.kind == 'app.fatal.dbLocked') {
      AppDiagnostics.error(
        'app.fatal',
        error,
        stackTrace: stackTrace,
        message: 'app.fatal.dbLocked',
        data: {
          'sqliteCode': classification.sqliteCode,
          'operationDomain': classification.operationDomain ?? 'unknown',
          'exceptionType': error.runtimeType.toString(),
          'phase': phase,
        },
      );
    }

    await flushDiagnostics();
  }

  Future<void> flushDiagnostics() async {
    await AppDiagnostics.flushPersisted();
    await Log.flushFileSink();
  }

  Map<String, Object?> pendingWriteSnapshot() {
    return {
      'pendingDbWrites': CanonicalDbWriteGate.pendingWrites,
      'pendingReaderSessionWrites': ReaderSessionRepository.pendingWrites,
      'pendingAppdataWrites': Appdata.pendingWrites,
    };
  }

  Future<bool> _waitForPendingWrites({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final noPending =
          CanonicalDbWriteGate.pendingWrites == 0 &&
          ReaderSessionRepository.pendingWrites == 0 &&
          Appdata.pendingWrites == 0;
      if (noPending) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return CanonicalDbWriteGate.pendingWrites == 0 &&
        ReaderSessionRepository.pendingWrites == 0 &&
        Appdata.pendingWrites == 0;
  }

  Future<void> _touchHeartbeat() async {
    final marker = await _readMarker();
    if (marker == null) {
      return;
    }
    marker['lastHeartbeatAt'] = DateTime.now().toUtc().toIso8601String();
    await _writeMarker(marker);
  }

  Future<Map<String, Object?>?> _readMarker() async {
    final file = File(_markerPath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final parsed = jsonDecode(await file.readAsString());
      if (parsed is Map) {
        return Map<String, Object?>.from(parsed);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeMarker(Map<String, Object?> marker) async {
    final file = File(_markerPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(marker), flush: true);
  }

  Map<String, Object?> _newMarker(Map<String, Object?>? previous) {
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'pid': pid,
      'appVersion': App.version,
      'platform': Platform.operatingSystem,
      'startedAt': now,
      'lastHeartbeatAt': now,
      'runtimeRoot': App.dataPath,
      if (previous != null)
        'previousMarkerState': _sanitizeMarkerForLog(previous),
    };
  }
}

class FatalClassification {
  const FatalClassification({
    required this.kind,
    this.sqliteCode,
    this.operationDomain,
  });

  final String kind;
  final int? sqliteCode;
  final String? operationDomain;
}

FatalClassification classifyFatal(Object error) {
  int? sqliteCode;
  String? operationDomain;
  sqliteCode = CanonicalDbWriteGate.extractSqliteCode(error);
  final message = error.toString().toLowerCase();

  if (message.contains('reader')) {
    operationDomain = 'reader';
  } else if (message.contains('appdata')) {
    operationDomain = 'appdata';
  } else if (message.contains('local library') || message.contains('library')) {
    operationDomain = 'local_library';
  } else if (message.contains('import')) {
    operationDomain = 'import';
  }

  if (sqliteCode == 5 || sqliteCode == 517) {
    return FatalClassification(
      kind: 'app.fatal.dbLocked',
      sqliteCode: sqliteCode,
      operationDomain: operationDomain,
    );
  }
  return const FatalClassification(kind: 'app.fatal.uncaught');
}
