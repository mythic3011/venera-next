import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/features/reader_next/importer/models.dart';
import 'package:venera/features/reader_next/importer/runtime_backup.dart';

class LegacyImportPreflightService {
  const LegacyImportPreflightService({
    RuntimeDatabaseBackupService backupService =
        const RuntimeDatabaseBackupService(),
  }) : _backupService = backupService;

  final RuntimeDatabaseBackupService _backupService;

  Future<LegacyImportPreflightReport> run({
    required String legacyDbPath,
    required String runtimeDbPath,
    required String backupDirectoryPath,
    DateTime? now,
  }) async {
    final backupPath = await _backupService.backup(
      runtimeDbPath: runtimeDbPath,
      backupDirectoryPath: backupDirectoryPath,
      now: now,
    );

    final legacyFile = File(legacyDbPath);
    if (!legacyFile.existsSync()) {
      return LegacyImportPreflightReport(
        legacyDbPath: legacyDbPath,
        runtimeDbPath: runtimeDbPath,
        backupPath: backupPath,
        runtimeBackupCreated: true,
        legacyDbExists: false,
        legacyTables: const <String>[],
        legacySchemaWarnings: const <String>['legacy_db_missing'],
      );
    }

    final db = sqlite.sqlite3.open(legacyDbPath);
    try {
      final tableRows = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name ASC;",
      );
      final tables = tableRows
          .map((row) => row['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      final warnings = _scanWarnings(db, tables);
      return LegacyImportPreflightReport(
        legacyDbPath: legacyDbPath,
        runtimeDbPath: runtimeDbPath,
        backupPath: backupPath,
        runtimeBackupCreated: true,
        legacyDbExists: true,
        legacyTables: tables,
        legacySchemaWarnings: warnings,
      );
    } finally {
      db.dispose();
    }
  }

  List<String> _scanWarnings(sqlite.Database db, List<String> tables) {
    final warnings = <String>[];
    if (tables.contains('history')) {
      final columns = _tableColumns(db, 'history');
      for (final required in ['id', 'type', 'time', 'ep', 'page']) {
        if (!columns.contains(required)) {
          warnings.add('history_missing_column:$required');
        }
      }
    }
    if (tables.contains('comics')) {
      final columns = _tableColumns(db, 'comics');
      for (final required in ['id', 'title', 'comic_type']) {
        if (!columns.contains(required)) {
          warnings.add('comics_missing_column:$required');
        }
      }
    }
    return warnings;
  }

  Set<String> _tableColumns(sqlite.Database db, String table) {
    final rows = db.select('PRAGMA table_info("$table");');
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }
}
