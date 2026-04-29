import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart' as talker;
import 'package:venera/foundation/log.dart' as legacy_log;

const bool _envDiagnosticsEnabled = bool.fromEnvironment(
  'APP_DEBUG_DIAGNOSTICS',
);

bool diagnosticsEnabled({required bool isDebugMode, required bool envEnabled}) {
  return isDebugMode || envEnabled;
}

enum DiagnosticLevel {
  trace,
  info,
  warn,
  error;

  bool allows(DiagnosticLevel minLevel) => index >= minLevel.index;
}

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.level,
    required this.channel,
    required this.message,
    this.data = const {},
    this.errorType,
    this.stackTrace,
    this.correlationId,
  });

  final DateTime timestamp;
  final DiagnosticLevel level;
  final String channel;
  final String message;
  final Map<String, Object?> data;
  final String? errorType;
  final String? stackTrace;
  final String? correlationId;

  Map<String, Object?> toJson() {
    return {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'level': level.name,
      'channel': channel,
      'message': message,
      'data': data,
      if (errorType != null) 'errorType': errorType,
      if (stackTrace != null) 'stackTrace': stackTrace,
      if (correlationId != null) 'correlationId': correlationId,
    };
  }
}

abstract interface class DiagnosticSink {
  void record(DiagnosticEvent event);
}

abstract final class DiagnosticsRedactor {
  static const _redacted = '[redacted]';

  static Object? redact(Object? value) {
    if (value is String) {
      return redactText(value);
    }
    if (value is Uri) {
      return _redactUriText(value.toString());
    }
    if (value is Map) {
      return value.map<String, Object?>((key, val) {
        final keyText = key.toString();
        if (_isSensitiveKey(keyText)) {
          return MapEntry(keyText, _redacted);
        }
        return MapEntry(keyText, redact(val));
      });
    }
    if (value is Iterable) {
      return value.map(redact).toList(growable: false);
    }
    return value;
  }

  static Map<String, Object?> redactMap(Map<String, Object?> value) {
    return redact(value)! as Map<String, Object?>;
  }

  static String redactText(String text) {
    var redacted = text.replaceAllMapped(RegExp("https?://[^\\s\\]\\)\"']+"), (
      match,
    ) {
      final raw = match.group(0)!;
      final uri = Uri.tryParse(raw);
      if (uri == null || !uri.hasQuery) {
        return raw;
      }
      return _redactUriText(uri.toString());
    });

    redacted = redacted.replaceAllMapped(
      RegExp(
        r'^\s*(authorization|cookie|set-cookie)\s*:\s*.+$',
        caseSensitive: false,
        multiLine: true,
      ),
      (match) => '${match.group(1)}: $_redacted',
    );

    redacted = redacted.replaceAllMapped(
      RegExp(
        r'\b(token|access_token|refresh_token|password|passwd|cookie|authorization|auth|account|session)\s*=\s*[^\s&;]+',
        caseSensitive: false,
      ),
      (match) {
        final source = match.group(0)!;
        final index = source.indexOf('=');
        if (index < 0) return _redacted;
        return '${source.substring(0, index)}=$_redacted';
      },
    );

    return redacted;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('cookie') ||
        normalized.contains('authorization') ||
        normalized.contains('password') ||
        normalized.contains('passwd') ||
        normalized.contains('session') ||
        normalized.contains('account');
  }

  static String _redactUriText(String value) {
    final queryIndex = value.indexOf('?');
    if (queryIndex < 0) {
      return value;
    }
    return '${value.substring(0, queryIndex)}?$_redacted';
  }
}

class DiagnosticRingBuffer implements DiagnosticSink {
  DiagnosticRingBuffer({this.maxEvents = 500});

  final int maxEvents;
  final List<DiagnosticEvent> _events = [];

  @override
  void record(DiagnosticEvent event) {
    if (_events.length >= maxEvents) {
      _events.removeAt(0);
    }
    _events.add(event);
  }

  List<DiagnosticEvent> recent({String? channel, DiagnosticLevel? minLevel}) {
    final min = minLevel ?? DiagnosticLevel.trace;
    return _events
        .where((event) {
          return event.level.allows(min) &&
              (channel == null || event.channel == channel);
        })
        .toList(growable: false);
  }

  void clear() => _events.clear();
}

class _TalkerDiagnosticSink implements DiagnosticSink {
  const _TalkerDiagnosticSink(this._talker);

  final talker.Talker _talker;

  @override
  void record(DiagnosticEvent event) {
    final message = _format(event);
    switch (event.level) {
      case DiagnosticLevel.trace:
        _talker.debug(message);
      case DiagnosticLevel.info:
        _talker.info(message);
      case DiagnosticLevel.warn:
        _talker.warning(message);
      case DiagnosticLevel.error:
        _talker.error(message);
    }
  }
}

class _DeveloperLogDiagnosticSink implements DiagnosticSink {
  const _DeveloperLogDiagnosticSink();

  @override
  void record(DiagnosticEvent event) {
    developer.log(
      event.message,
      name: event.channel,
      level: switch (event.level) {
        DiagnosticLevel.trace => 500,
        DiagnosticLevel.info => 800,
        DiagnosticLevel.warn => 900,
        DiagnosticLevel.error => 1000,
      },
      error: event.errorType,
      stackTrace: event.stackTrace == null
          ? null
          : StackTrace.fromString(event.stackTrace!),
    );
  }
}

class _LegacyLogDiagnosticSink implements DiagnosticSink {
  const _LegacyLogDiagnosticSink();

  @override
  void record(DiagnosticEvent event) {
    switch (event.level) {
      case DiagnosticLevel.trace:
      case DiagnosticLevel.info:
        return;
      case DiagnosticLevel.warn:
        legacy_log.Log.warning(event.channel, _format(event));
      case DiagnosticLevel.error:
        legacy_log.Log.error(event.channel, _format(event));
    }
  }
}

String _format(DiagnosticEvent event) {
  final data = event.data.isEmpty ? '' : ' ${jsonEncode(event.data)}';
  final error = event.errorType == null ? '' : ' errorType=${event.errorType}';
  return '[${event.level.name}] ${event.channel}: ${event.message}$error$data';
}

final talker.Talker appTalker = talker.Talker();

abstract final class AppDiagnostics {
  static final DiagnosticRingBuffer _ringBuffer = DiagnosticRingBuffer();
  static DiagnosticLevel _runtimeLevel = DiagnosticLevel.trace;
  static List<DiagnosticSink> _sinks = _defaultSinks();

  static void trace(
    String channel,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _record(
      level: DiagnosticLevel.trace,
      channel: channel,
      message: message,
      data: data,
    );
  }

  static void info(
    String channel,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _record(
      level: DiagnosticLevel.info,
      channel: channel,
      message: message,
      data: data,
    );
  }

  static void warn(
    String channel,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _record(
      level: DiagnosticLevel.warn,
      channel: channel,
      message: message,
      data: data,
    );
  }

  static void error(
    String channel,
    Object error, {
    StackTrace? stackTrace,
    String? message,
    Map<String, Object?> data = const {},
  }) {
    _record(
      level: DiagnosticLevel.error,
      channel: channel,
      message: message ?? error.toString(),
      data: data,
      errorType: error.runtimeType.toString(),
      stackTrace: stackTrace?.toString(),
    );
  }

  static List<DiagnosticEvent> recent({
    String? channel,
    DiagnosticLevel? minLevel,
  }) {
    return _ringBuffer.recent(channel: channel, minLevel: minLevel);
  }

  static String exportNdjson({String? channel, DiagnosticLevel? minLevel}) {
    return recent(
      channel: channel,
      minLevel: minLevel,
    ).map((event) => jsonEncode(event.toJson())).join('\n');
  }

  static void setRuntimeLevel(DiagnosticLevel level) {
    _runtimeLevel = level;
  }

  static DiagnosticLevel get runtimeLevel => _runtimeLevel;

  static void clear() {
    _ringBuffer.clear();
    appTalker.cleanHistory();
  }

  @visibleForTesting
  static void configureSinksForTesting(List<DiagnosticSink> sinks) {
    _sinks = [_ringBuffer, ...sinks];
  }

  @visibleForTesting
  static void resetForTesting() {
    _runtimeLevel = DiagnosticLevel.trace;
    _ringBuffer.clear();
    _sinks = _defaultSinks();
    appTalker.cleanHistory();
  }

  static void _record({
    required DiagnosticLevel level,
    required String channel,
    required String message,
    Map<String, Object?> data = const {},
    String? errorType,
    String? stackTrace,
  }) {
    if (!level.allows(_runtimeLevel)) {
      return;
    }
    final event = DiagnosticEvent(
      timestamp: DateTime.now(),
      level: level,
      channel: channel,
      message: DiagnosticsRedactor.redactText(message),
      data: DiagnosticsRedactor.redactMap(data),
      errorType: errorType,
      stackTrace: stackTrace == null
          ? null
          : DiagnosticsRedactor.redactText(stackTrace),
    );
    for (final sink in _sinks) {
      sink.record(event);
    }
  }

  static List<DiagnosticSink> _defaultSinks() {
    return [
      _ringBuffer,
      _TalkerDiagnosticSink(appTalker),
      const _DeveloperLogDiagnosticSink(),
      const _LegacyLogDiagnosticSink(),
    ];
  }
}

abstract final class DevDiagnosticsApi {
  @visibleForTesting
  static bool? debugEnabledOverride;

  static bool get isEnabled {
    final override = debugEnabledOverride;
    if (override != null) {
      return override;
    }
    return diagnosticsEnabled(
      isDebugMode: kDebugMode,
      envEnabled: _envDiagnosticsEnabled,
    );
  }

  static List<DiagnosticEvent> recent({
    String? channel,
    DiagnosticLevel? minLevel,
  }) {
    return AppDiagnostics.recent(channel: channel, minLevel: minLevel);
  }

  static String exportNdjson({String? channel, DiagnosticLevel? minLevel}) {
    return AppDiagnostics.exportNdjson(channel: channel, minLevel: minLevel);
  }

  static void setRuntimeLevel(DiagnosticLevel level) {
    AppDiagnostics.setRuntimeLevel(level);
  }

  static void clear() {
    AppDiagnostics.clear();
  }
}
