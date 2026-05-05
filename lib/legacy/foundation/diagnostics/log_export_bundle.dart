import 'dart:convert';

import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/utils/io.dart';

Future<List<File>> _listStructuredArchiveFiles() async {
  if (!App.isInitialized) {
    return const [];
  }
  final logsDir = Directory(FilePath.join(App.dataPath, 'logs'));
  if (!await logsDir.exists()) {
    return const [];
  }
  final baseName = 'diagnostics.ndjson';
  final entities = await logsDir.list().toList();
  final files = entities
      .whereType<File>()
      .where((file) {
        final name = file.uri.pathSegments.last;
        return name == baseName || name.startsWith('$baseName.');
      })
      .toList(growable: false);
  files.sort((a, b) {
    final aName = a.uri.pathSegments.last;
    final bName = b.uri.pathSegments.last;
    if (aName == baseName) return -1;
    if (bName == baseName) return 1;
    return bName.compareTo(aName);
  });
  return files;
}

Future<String> _readStructuredFileForExport(File file) async {
  if (file.path.endsWith('.gz')) {
    final bytes = await file.readAsBytes();
    return utf8.decode(gzip.decode(bytes), allowMalformed: true);
  }
  return file.readAsString();
}

Future<String> buildDiagnosticsExportText() async {
  final buffer = StringBuffer();
  final structuredFiles = await _listStructuredArchiveFiles();
  final archiveFiles = structuredFiles
      .where((file) => file.uri.pathSegments.last != 'diagnostics.ndjson')
      .toList(growable: false);

  final manifest = <String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'runtimeLevel': AppDiagnostics.runtimeLevel.name,
    'persistedLevel': AppDiagnostics.persistedLevel.name,
    'includedArchives': archiveFiles.length,
    'structuredFiles': structuredFiles
        .map((file) => file.uri.pathSegments.last)
        .toList(growable: false),
  };

  buffer.writeln("=== Diagnostics Export Manifest (JSON) ===");
  buffer.writeln(jsonEncode(manifest));
  buffer.writeln();

  buffer.writeln("=== Structured Diagnostics (NDJSON) ===");
  if (structuredFiles.isEmpty) {
    final structuredNdjson = DevDiagnosticsApi.exportNdjson();
    if (structuredNdjson.trim().isEmpty) {
      buffer.writeln("(no structured diagnostics events)");
    } else {
      buffer.writeln(structuredNdjson);
    }
  } else {
    for (final file in structuredFiles) {
      final name = file.uri.pathSegments.last;
      final content = await _readStructuredFileForExport(file);
      buffer.writeln('--- $name ---');
      if (content.trim().isEmpty) {
        buffer.writeln('(empty)');
      } else {
        buffer.writeln(content);
      }
      if (!content.endsWith('\n')) {
        buffer.writeln();
      }
    }
  }
  buffer.writeln();

  buffer.writeln("=== Crash Runtime Metadata (JSON) ===");
  buffer.writeln(jsonEncode(await _buildCrashRuntimeMetadata()));
  buffer.writeln();

  buffer.writeln("=== Previous Lifecycle Marker (JSON) ===");
  final marker = await _readLifecycleMarker();
  if (marker == null) {
    buffer.writeln('(missing)');
  } else {
    final sanitized = Map<String, Object?>.from(marker);
    sanitized.remove('runtimeRoot');
    if (sanitized['previousMarkerState'] is Map) {
      final previousState = Map<String, Object?>.from(
        sanitized['previousMarkerState'] as Map,
      );
      previousState.remove('runtimeRoot');
      sanitized['previousMarkerState'] = previousState;
    }
    buffer.writeln(jsonEncode(sanitized));
  }
  buffer.writeln();

  buffer.writeln("=== DB Lock Summary (JSON) ===");
  buffer.writeln(jsonEncode(_dbLockSummary()));
  buffer.writeln();

  buffer.writeln("=== Reader Trace Snapshot (JSON) ===");
  buffer.writeln(jsonEncode(_readerTraceSnapshot()));
  buffer.writeln();

  buffer.writeln("=== Legacy Log Tail (logs.txt) ===");
  final tail = await _readLegacyLogTail(maxLines: 200);
  if (tail.trim().isEmpty) {
    buffer.writeln('(empty)');
  } else {
    buffer.writeln(tail);
  }
  buffer.writeln();

  buffer.write(await Log.buildExportText());
  return buffer.toString();
}

Future<Map<String, Object?>> _buildCrashRuntimeMetadata() async {
  return {
    'appVersion': App.version,
    'platform': {'os': Platform.operatingSystem, 'isDesktop': App.isDesktop},
    'runtime': {
      'runtimeRootBase': App.runtimeRootBasePath,
      'runtimeRootOverrideActive': App.runtimeRootOverrideActive,
    },
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

Future<Map<String, Object?>?> _readLifecycleMarker() async {
  if (!App.isInitialized) {
    return null;
  }
  final markerFile = File(
    FilePath.join(App.dataPath, 'runtime', 'lifecycle_marker.json'),
  );
  if (!await markerFile.exists()) {
    return null;
  }
  final parsed = jsonDecode(await markerFile.readAsString());
  if (parsed is! Map) {
    return null;
  }
  return Map<String, Object?>.from(parsed);
}

Map<String, Object?> _dbLockSummary() {
  final events = DevDiagnosticsApi.recent(channel: 'app.fatal');
  final byCode = <String, int>{};
  var total = 0;
  for (final event in events) {
    if (event.message != 'app.fatal.dbLocked') {
      continue;
    }
    total++;
    final code = '${event.data['sqliteCode'] ?? 'unknown'}';
    byCode[code] = (byCode[code] ?? 0) + 1;
  }
  return {'total': total, 'bySqliteCode': byCode};
}

Map<String, Object?> _readerTraceSnapshot() {
  final data = ReaderDiagnostics.toDiagnosticsJson();
  final trace = data['readerTrace'];
  if (trace is Map<String, dynamic>) {
    return Map<String, Object?>.from(trace);
  }
  return const {'available': false};
}

Future<String> _readLegacyLogTail({required int maxLines}) async {
  final path = Log.logFilePath;
  if (path == null) {
    return '';
  }
  final file = File(path);
  if (!await file.exists()) {
    return '';
  }
  final lines = await file.readAsLines();
  if (lines.length <= maxLines) {
    return lines.join('\n');
  }
  return lines.sublist(lines.length - maxLines).join('\n');
}

Future<File?> exportDiagnosticsToFile({String? outputPath}) async {
  if (!App.isInitialized) {
    return null;
  }
  final outPath =
      outputPath ??
      Directory(App.dataPath)
          .joinFile(
            Log.buildExportFileName(prefix: 'venera_diagnostics_export'),
          )
          .path;
  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(await buildDiagnosticsExportText());
  return file;
}

Future<File?> exportCrashReportBundleToFile({String? outputPath}) async {
  if (!App.isInitialized) {
    return null;
  }
  final outPath =
      outputPath ??
      Directory(App.dataPath)
          .joinFile(
            Log.buildExportFileName(prefix: 'venera_crash_report_bundle'),
          )
          .path;
  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(await buildDiagnosticsExportText());
  return file;
}
