import 'dart:convert';

import 'package:venera/foundation/log.dart';
import 'package:venera/utils/io.dart';

class SerializedLogItem {
  final LogLevel level;
  final String title;
  final String content;
  final DateTime time;
  final String source;

  const SerializedLogItem({
    required this.level,
    required this.title,
    required this.content,
    required this.time,
    required this.source,
  });
}

class LogDiagnosticSnapshot {
  final List<Map<String, Object?>> logs;
  final List<Map<String, Object?>> groupedIssues;
  final int sessionTotalCount;
  final int persistedTotalCount;
  final int sessionErrorCount;
  final int persistedErrorCount;

  const LogDiagnosticSnapshot({
    required this.logs,
    required this.groupedIssues,
    required this.sessionTotalCount,
    required this.persistedTotalCount,
    required this.sessionErrorCount,
    required this.persistedErrorCount,
  });

  int get totalCount => sessionTotalCount + persistedTotalCount;

  int get errorCount => sessionErrorCount + persistedErrorCount;
}

class LogDiagnostics {
  LogDiagnostics._();

  static Future<List<SerializedLogItem>> persistedLogs() async {
    await Log.flushFileSink();
    final path = Log.logFilePath;
    if (path == null) {
      return const [];
    }
    final file = File(path);
    if (!await file.exists()) {
      return const [];
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return const [];
    }
    return parsePersistedLogs(content);
  }

  static Future<LogDiagnosticSnapshot> diagnosticSnapshot({
    String level = "all",
    int limit = 200,
  }) async {
    final sessionLogs = Log.newest(
      level: level,
      limit: limit,
    ).map(Log.serialize);
    final persisted = await LogDiagnostics.persistedLogs();
    final persistedItems = newestFromPersisted(
      persisted,
      level: level,
      limit: limit,
    ).map(serializePersisted);
    final logs = [...sessionLogs, ...persistedItems].toList()
      ..sort((a, b) => b['time'].toString().compareTo(a['time'].toString()));
    final limited = logs.take(limit).toList(growable: false);

    return LogDiagnosticSnapshot(
      logs: limited,
      groupedIssues: _buildGroupedIssues(limited),
      sessionTotalCount: Log.logs.length,
      persistedTotalCount: persisted.length,
      sessionErrorCount: Log.logs
          .where((item) => item.level == LogLevel.error)
          .length,
      persistedErrorCount: persisted
          .where((item) => item.level == LogLevel.error)
          .length,
    );
  }

  static Map<String, Object?> serializePersisted(SerializedLogItem item) {
    return {
      "level": item.level.name,
      "title": item.title,
      "content": item.content,
      "time": item.time.toIso8601String(),
      "source": item.source,
    };
  }

  static List<SerializedLogItem> newestFromPersisted(
    List<SerializedLogItem> logs, {
    required String level,
    required int limit,
  }) {
    final normalizedLevel = parseLogLevel(level);
    final candidates = normalizedLevel == null
        ? logs
        : logs.where((item) => item.level == normalizedLevel);
    return candidates.toList().reversed.take(limit).toList(growable: false);
  }

  static LogLevel? parseLogLevel(String level) {
    return switch (level.toLowerCase()) {
      "info" => LogLevel.info,
      "warning" => LogLevel.warning,
      "error" => LogLevel.error,
      _ => null,
    };
  }

  static List<SerializedLogItem> parsePersistedLogs(String content) {
    final header = RegExp(
      r'^(error|warning|info) (.+) (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\s*$',
      multiLine: true,
    );
    final matches = header.allMatches(content).toList(growable: false);
    final items = <SerializedLogItem>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final next = i + 1 < matches.length
          ? matches[i + 1].start
          : content.length;
      final level = parseLogLevel(match.group(1)!);
      final time = DateTime.tryParse(match.group(3)!);
      if (level == null || time == null) {
        continue;
      }
      var body = content.substring(match.end, next);
      body = body.replaceFirst(RegExp(r'^\r?\n'), '');
      body = body.replaceFirst(RegExp(r'(\r?\n){0,2}$'), '');
      items.add(
        SerializedLogItem(
          level: level,
          title: match.group(2)!,
          content: body,
          time: time,
          source: "persisted",
        ),
      );
    }
    return items;
  }

  static final RegExp _projectedLegacyPattern = RegExp(
    r'^\[(error|warning|info)\]\s+([a-zA-Z0-9._-]+):\s+(.+?)(?:\s+errorType=([A-Za-z0-9_.$-]+))?(?:\s+(\{.*\}))?$',
    dotAll: true,
  );

  static List<Map<String, Object?>> _buildGroupedIssues(
    List<Map<String, Object?>> logs,
  ) {
    final grouped = <String, _GroupedIssueAccumulator>{};
    for (final entry in logs) {
      final parsed = _parseEntry(entry);
      final signature = parsed.signature;
      final existing = grouped[signature];
      if (existing == null) {
        grouped[signature] = _GroupedIssueAccumulator(parsed, entry);
      } else {
        existing.add(parsed, entry);
      }
    }
    final issues = grouped.values.map((issue) => issue.toJson()).toList()
      ..sort(
        (a, b) =>
            b['latestTime'].toString().compareTo(a['latestTime'].toString()),
      );
    return issues;
  }

  static _ParsedEntry _parseEntry(Map<String, Object?> entry) {
    final title = entry['title']?.toString() ?? '';
    final content = entry['content']?.toString() ?? '';
    final parsed = _projectedLegacyPattern.firstMatch(content.trim());
    if (parsed == null) {
      final normalizedContent = _normalizeText(content);
      return _ParsedEntry(
        signature: 'fallback|$title|$normalizedContent',
        message: title,
        fields: <String, Object?>{
          'fallbackTitle': title,
          'fallbackContent': normalizedContent,
        },
      );
    }

    Map<String, Object?> data = const <String, Object?>{};
    final rawJson = parsed.group(5);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic>) {
          data = decoded.map<String, Object?>(
            (key, value) => MapEntry(key, value),
          );
        }
      } catch (_) {}
    }

    final message = parsed.group(3)?.trim() ?? title;
    final diagnosticCode = data['diagnosticCode']?.toString();
    final sanitizedMessage = data['sanitizedMessage']?.toString();
    final exceptionType =
        data['exceptionType']?.toString() ?? parsed.group(4)?.toString();
    final pageOwner = data['pageOwner']?.toString();
    final tabOwner = data['tabOwner']?.toString();
    final signatureParts = <String>[
      title,
      message,
      if (diagnosticCode != null) diagnosticCode,
      if (sanitizedMessage != null) sanitizedMessage,
      if (exceptionType != null) exceptionType,
      if (pageOwner != null) pageOwner,
      if (tabOwner != null) tabOwner,
    ];
    final fields = <String, Object?>{
      if (diagnosticCode != null) 'diagnosticCode': diagnosticCode,
      if (sanitizedMessage != null) 'sanitizedMessage': sanitizedMessage,
      if (exceptionType != null) 'exceptionType': exceptionType,
      if (pageOwner != null) 'pageOwner': pageOwner,
      if (tabOwner != null) 'tabOwner': tabOwner,
      if (data['routeHash'] != null) 'routeHash': data['routeHash'],
      if (data['routeDiagnosticIdentity'] != null)
        'routeDiagnosticIdentity': data['routeDiagnosticIdentity'],
    };
    return _ParsedEntry(
      signature: signatureParts.join('|'),
      message: message,
      fields: fields,
    );
  }

  static String _normalizeText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _ParsedEntry {
  const _ParsedEntry({
    required this.signature,
    required this.message,
    required this.fields,
  });

  final String signature;
  final String message;
  final Map<String, Object?> fields;
}

class _GroupedIssueAccumulator {
  _GroupedIssueAccumulator(this._parsed, Map<String, Object?> firstEntry) {
    add(_parsed, firstEntry);
  }

  final _ParsedEntry _parsed;
  final Map<String, int> _sourceCount = <String, int>{};
  final Set<String> _routeHashes = <String>{};
  int _count = 0;
  DateTime? _latestTime;
  Map<String, Object?>? _latestEntry;

  void add(_ParsedEntry parsed, Map<String, Object?> entry) {
    _count++;
    final source = entry['source']?.toString() ?? 'unknown';
    _sourceCount[source] = (_sourceCount[source] ?? 0) + 1;
    final routeHash = parsed.fields['routeHash'];
    if (routeHash != null) {
      _routeHashes.add(routeHash.toString());
    }
    final time = DateTime.tryParse(entry['time']?.toString() ?? '');
    if (_latestTime == null || (time != null && time.isAfter(_latestTime!))) {
      _latestTime = time;
      _latestEntry = entry;
    }
  }

  Map<String, Object?> toJson() {
    final latestTime = _latestTime?.toIso8601String() ?? '';
    return <String, Object?>{
      'signature': _parsed.signature,
      'message': _parsed.message,
      'latestTime': latestTime,
      'occurrenceCount': _count,
      'sources': {
        'session': {'count': _sourceCount['session'] ?? 0},
        'persisted': {'count': _sourceCount['persisted'] ?? 0},
      },
      'latestEntry': _latestEntry,
      'fields': {
        ..._parsed.fields,
        if (_routeHashes.isNotEmpty) 'latestRouteHash': _routeHashes.last,
      },
      if (_routeHashes.isNotEmpty)
        'sampleRouteHashes': _routeHashes.toList(growable: false),
    };
  }
}
