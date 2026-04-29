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
  final int sessionTotalCount;
  final int persistedTotalCount;
  final int sessionErrorCount;
  final int persistedErrorCount;

  const LogDiagnosticSnapshot({
    required this.logs,
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

    return LogDiagnosticSnapshot(
      logs: logs.take(limit).toList(growable: false),
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
}
