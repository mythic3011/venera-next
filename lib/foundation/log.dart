import 'package:flutter/foundation.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/io.dart';

class LogItem {
  final LogLevel level;
  final String title;
  final String content;
  final DateTime time = DateTime.now();

  @override
  toString() => "${level.name} $title $time \n$content\n\n";

  LogItem(this.level, this.title, this.content);
}

enum LogLevel { error, warning, info }

class Log {
  static final List<LogItem> _logs = <LogItem>[];

  static List<LogItem> get logs => _logs;

  static const maxLogLength = 3000;

  static const maxLogNumber = 500;

  static String? get logFilePath {
    if (!App.isInitialized) {
      return null;
    }
    if (App.isAndroid) {
      if (App.externalStoragePath == null) {
        return null;
      }
      return Directory(App.externalStoragePath!).joinFile("logs.txt").path;
    }
    return Directory(App.dataPath).joinFile("logs.txt").path;
  }

  static bool ignoreLimitation = false;

  static bool isMuted = false;

  static void printWarning(String text) {
    debugPrint('\x1B[33m$text\x1B[0m');
  }

  static void printError(String text) {
    debugPrint('\x1B[31m$text\x1B[0m');
  }

  static IOSink? _file;

  static String _buildExportFileName() {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return "logs_export_$stamp.txt";
  }

  static String _platformName() {
    if (App.isAndroid) return "android";
    if (App.isIOS) return "ios";
    if (App.isWindows) return "windows";
    if (App.isMacOS) return "macos";
    if (App.isLinux) return "linux";
    return "unknown";
  }

  static void addLog(LogLevel level, String title, String content) {
    if (isMuted) return;
    if (_file == null && App.isInitialized) {
      var path = logFilePath;
      if (path != null) {
        var file = File(path);
        file.parent.createSync(recursive: true);
        _file = file.openWrite(mode: FileMode.append);
      }
    }

    if (!ignoreLimitation && content.length > maxLogLength) {
      content = "${content.substring(0, maxLogLength)}...";
    }

    switch (level) {
      case LogLevel.error:
        printError(content);
      case LogLevel.warning:
        printWarning(content);
      case LogLevel.info:
        if (kDebugMode) {
          debugPrint(content);
        }
    }

    var newLog = LogItem(level, title, content);

    if (newLog == _logs.lastOrNull) {
      return;
    }

    _logs.add(newLog);
    if (_file != null) {
      _file!.write(newLog.toString());
    }
    if (_logs.length > maxLogNumber) {
      var res = _logs.remove(
        _logs.firstWhereOrNull((element) => element.level == LogLevel.info),
      );
      if (!res) {
        _logs.removeAt(0);
      }
    }
  }

  static info(String title, String content) {
    addLog(LogLevel.info, title, content);
  }

  static warning(String title, String content) {
    addLog(LogLevel.warning, title, content);
  }

  static error(String title, Object content, [Object? stackTrace]) {
    var info = content.toString();
    if (stackTrace != null) {
      info += "\n${stackTrace.toString()}";
    }
    addLog(LogLevel.error, title, info);
  }

  static void clear() => _logs.clear();

  static Future<void> closeFileSink() async {
    final sink = _file;
    _file = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  static Future<void> flushFileSink() async {
    await _file?.flush();
  }

  static Future<File?> exportToFile({String? outputPath}) async {
    if (!App.isInitialized) {
      return null;
    }
    await _file?.flush();
    final outPath =
        outputPath ??
        Directory(App.dataPath).joinFile(_buildExportFileName()).path;
    final file = File(outPath);
    await file.parent.create(recursive: true);
    final exportText = await buildExportText();
    await file.writeAsString(exportText, mode: FileMode.write);
    return file;
  }

  static Future<String> buildExportText() async {
    await _file?.flush();

    final buffer = StringBuffer();
    final now = DateTime.now().toIso8601String();
    final persistedPath = logFilePath;
    final appDataPath = App.isInitialized ? App.dataPath : "(uninitialized)";

    buffer.writeln("Venera Logs Export");
    buffer.writeln("Exported At: $now");
    buffer.writeln("App Version: ${App.version}");
    buffer.writeln("Platform: ${_platformName()}");
    buffer.writeln("App Data Path: $appDataPath");
    buffer.writeln("Log File Path: ${persistedPath ?? '(unavailable)'}");
    buffer.writeln();

    buffer.writeln("=== Current Session Logs ===");
    if (_logs.isEmpty) {
      buffer.writeln("(no in-memory session logs)");
    } else {
      for (final item in _logs) {
        buffer.write(item.toString());
      }
    }
    buffer.writeln();

    buffer.writeln("=== Persisted Log File ===");
    if (persistedPath == null) {
      buffer.writeln("(log file path unavailable: app not initialized)");
      return buffer.toString();
    }

    final persistedFile = File(persistedPath);
    if (!await persistedFile.exists()) {
      buffer.writeln("(persisted log file does not exist)");
      return buffer.toString();
    }

    final persistedContent = await persistedFile.readAsString();
    if (persistedContent.trim().isEmpty) {
      buffer.writeln("(persisted log file is empty)");
    } else {
      buffer.write(persistedContent);
      if (!persistedContent.endsWith('\n')) {
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  static Map<String, Object?> serialize(LogItem item) {
    return {
      "level": item.level.name,
      "title": item.title,
      "content": item.content,
      "time": item.time.toIso8601String(),
      "source": "session",
    };
  }

  static List<LogItem> newest({String level = "all", int limit = 200}) {
    final normalizedLevel = switch (level.toLowerCase()) {
      "info" => LogLevel.info,
      "warning" => LogLevel.warning,
      "error" => LogLevel.error,
      _ => null,
    };

    final candidates = normalizedLevel == null
        ? _logs
        : _logs.where((item) => item.level == normalizedLevel);

    return candidates.toList().reversed.take(limit).toList(growable: false);
  }

  @override
  String toString() {
    var res = "Logs\n\n";
    for (var log in _logs) {
      res += log.toString();
    }
    return res;
  }
}
