import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/features/reader_next/importer/legacy_import_preflight.dart';
import 'package:venera/features/reader_next/importer/legacy_import_validation.dart';
import 'package:venera/features/reader_next/importer/models.dart';

abstract interface class LegacyImportApplySink {
  Future<void> importHistoryRow(LegacyHistoryImportRow row);

  Future<void> importComicsRow(LegacyComicsImportRow row);
}

abstract interface class LegacyImportTransactionRunner {
  Future<T> runInTransaction<T>(Future<T> Function() action);
}

class NoopLegacyImportTransactionRunner
    implements LegacyImportTransactionRunner {
  const NoopLegacyImportTransactionRunner();

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) => action();
}

class LegacyImportExecutionService {
  const LegacyImportExecutionService({
    required LegacyImportApplySink sink,
    LegacyImportPreflightService preflightService =
        const LegacyImportPreflightService(),
    LegacyImportValidationService validationService =
        const LegacyImportValidationService(),
    LegacyImportTransactionRunner transactionRunner =
        const NoopLegacyImportTransactionRunner(),
  }) : _sink = sink,
       _preflightService = preflightService,
       _validationService = validationService,
       _transactionRunner = transactionRunner;

  final LegacyImportApplySink _sink;
  final LegacyImportPreflightService _preflightService;
  final LegacyImportValidationService _validationService;
  final LegacyImportTransactionRunner _transactionRunner;

  Future<LegacyImportExecutionReport> run({
    required LegacyImportExecutionMode mode,
    required String legacyDbPath,
    required String runtimeDbPath,
    required String backupDirectoryPath,
    required String checkpointDirectoryPath,
    DateTime? now,
  }) async {
    final preflight = await _preflightService.run(
      legacyDbPath: legacyDbPath,
      runtimeDbPath: runtimeDbPath,
      backupDirectoryPath: backupDirectoryPath,
      now: now,
    );
    final validation = await _validationService.validate(
      legacyDbPath: legacyDbPath,
    );
    final checkpointPath = _checkpointPath(checkpointDirectoryPath);
    final checkpoint = await _loadCheckpoint(checkpointPath);

    if (mode == LegacyImportExecutionMode.dryRun) {
      final artifactPath = await _writeDryRunArtifact(
        preflight: preflight,
        validation: validation,
        checkpoint: checkpoint,
        backupDirectoryPath: backupDirectoryPath,
        now: now,
      );
      return LegacyImportExecutionReport(
        mode: mode,
        preflight: preflight,
        validation: validation,
        appliedHistoryRows: 0,
        appliedComicsRows: 0,
        checkpoint: checkpoint,
        checkpointPath: checkpointPath,
        dryRunArtifactPath: artifactPath,
        completed: true,
      );
    }

    try {
      final result = await _transactionRunner.runInTransaction(
        () => _applyAll(
          legacyDbPath: legacyDbPath,
          initialCheckpoint: checkpoint,
          checkpointPath: checkpointPath,
        ),
      );
      return LegacyImportExecutionReport(
        mode: mode,
        preflight: preflight,
        validation: validation,
        appliedHistoryRows: result.appliedHistoryRows,
        appliedComicsRows: result.appliedComicsRows,
        checkpoint: result.checkpoint,
        checkpointPath: checkpointPath,
        completed: true,
      );
    } catch (e) {
      final latestCheckpoint = await _loadCheckpoint(checkpointPath);
      return LegacyImportExecutionReport(
        mode: mode,
        preflight: preflight,
        validation: validation,
        appliedHistoryRows: 0,
        appliedComicsRows: 0,
        checkpoint: latestCheckpoint,
        checkpointPath: checkpointPath,
        completed: false,
        failureCode: 'LEGACY_IMPORT_APPLY_FAILED',
        failureMessage: e.toString(),
      );
    }
  }

  String _checkpointPath(String checkpointDirectoryPath) {
    return '$checkpointDirectoryPath/legacy-import-checkpoint.json';
  }

  Future<LegacyImportCheckpoint> _loadCheckpoint(String checkpointPath) async {
    final checkpointFile = File(checkpointPath);
    if (!checkpointFile.existsSync()) {
      return const LegacyImportCheckpoint(historyRowId: 0, comicsRowId: 0);
    }
    try {
      final decoded = jsonDecode(await checkpointFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const LegacyImportCheckpoint(historyRowId: 0, comicsRowId: 0);
      }
      return LegacyImportCheckpoint.fromJson(decoded);
    } catch (_) {
      return const LegacyImportCheckpoint(historyRowId: 0, comicsRowId: 0);
    }
  }

  Future<void> _saveCheckpoint({
    required String checkpointPath,
    required LegacyImportCheckpoint checkpoint,
  }) async {
    final file = File(checkpointPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(checkpoint.toJson()));
  }

  Future<String> _writeDryRunArtifact({
    required LegacyImportPreflightReport preflight,
    required LegacyImportValidationReport validation,
    required LegacyImportCheckpoint checkpoint,
    required String backupDirectoryPath,
    DateTime? now,
  }) async {
    final dir = Directory(backupDirectoryPath);
    await dir.create(recursive: true);
    final timestamp = (now ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-');
    final artifactPath = '${dir.path}/legacy-import-dry-run-$timestamp.json';
    final payload = <String, dynamic>{
      'mode': 'dry_run',
      'legacyDbPath': preflight.legacyDbPath,
      'runtimeDbPath': preflight.runtimeDbPath,
      'runtimeBackupPath': preflight.backupPath,
      'legacyDbExists': preflight.legacyDbExists,
      'legacyTables': preflight.legacyTables,
      'legacySchemaWarnings': preflight.legacySchemaWarnings,
      'validation': <String, dynamic>{
        'totalRowsScanned': validation.totalRowsScanned,
        'rowsAccepted': validation.rowsAccepted,
        'rowsSkipped': validation.rowsSkipped,
        'skippedByCode': validation.skippedByCode,
      },
      'checkpoint': checkpoint.toJson(),
    };
    await File(artifactPath).writeAsString(jsonEncode(payload));
    return artifactPath;
  }

  Future<_ApplyResult> _applyAll({
    required String legacyDbPath,
    required LegacyImportCheckpoint initialCheckpoint,
    required String checkpointPath,
  }) async {
    final db = sqlite.sqlite3.open(legacyDbPath);
    try {
      var checkpoint = initialCheckpoint;
      var appliedHistoryRows = 0;
      var appliedComicsRows = 0;

      if (_tableExists(db, 'history')) {
        final historyRows = db.select(
          'SELECT rowid, id, type, time, ep, page FROM history WHERE rowid > ? ORDER BY rowid ASC;',
          [checkpoint.historyRowId],
        );
        for (final row in historyRows) {
          final rowId = row['rowid'] as int;
          final importedRow = _parseHistoryRow(row);
          if (importedRow != null) {
            await _sink.importHistoryRow(importedRow);
            appliedHistoryRows += 1;
          }
          checkpoint = LegacyImportCheckpoint(
            historyRowId: rowId,
            comicsRowId: checkpoint.comicsRowId,
          );
          await _saveCheckpoint(
            checkpointPath: checkpointPath,
            checkpoint: checkpoint,
          );
        }
      }

      if (_tableExists(db, 'comics')) {
        final comicsRows = db.select(
          'SELECT rowid, id, title, comic_type FROM comics WHERE rowid > ? ORDER BY rowid ASC;',
          [checkpoint.comicsRowId],
        );
        for (final row in comicsRows) {
          final rowId = row['rowid'] as int;
          final importedRow = _parseComicsRow(row);
          if (importedRow != null) {
            await _sink.importComicsRow(importedRow);
            appliedComicsRows += 1;
          }
          checkpoint = LegacyImportCheckpoint(
            historyRowId: checkpoint.historyRowId,
            comicsRowId: rowId,
          );
          await _saveCheckpoint(
            checkpointPath: checkpointPath,
            checkpoint: checkpoint,
          );
        }
      }

      return _ApplyResult(
        appliedHistoryRows: appliedHistoryRows,
        appliedComicsRows: appliedComicsRows,
        checkpoint: checkpoint,
      );
    } finally {
      db.dispose();
    }
  }

  bool _tableExists(sqlite.Database db, String tableName) {
    final rows = db.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  LegacyHistoryImportRow? _parseHistoryRow(sqlite.Row row) {
    final rowId = row['rowid'];
    final id = row['id']?.toString() ?? '';
    final type = row['type'];
    final time = row['time'];
    final ep = row['ep'];
    final page = row['page'];
    if (rowId is! int || id.isEmpty) {
      return null;
    }
    if (type is! int || time is! int || ep is! int || page is! int) {
      return null;
    }
    if (time < 0 || ep < 0 || page < 0) {
      return null;
    }
    return LegacyHistoryImportRow(
      rowId: rowId,
      id: id,
      type: type,
      time: time,
      ep: ep,
      page: page,
    );
  }

  LegacyComicsImportRow? _parseComicsRow(sqlite.Row row) {
    final rowId = row['rowid'];
    final id = row['id']?.toString() ?? '';
    final title = row['title']?.toString() ?? '';
    final comicType = row['comic_type'];
    if (rowId is! int || id.isEmpty || title.isEmpty || comicType is! int) {
      return null;
    }
    return LegacyComicsImportRow(
      rowId: rowId,
      id: id,
      title: title,
      comicType: comicType,
    );
  }
}

class _ApplyResult {
  const _ApplyResult({
    required this.appliedHistoryRows,
    required this.appliedComicsRows,
    required this.checkpoint,
  });

  final int appliedHistoryRows;
  final int appliedComicsRows;
  final LegacyImportCheckpoint checkpoint;
}
