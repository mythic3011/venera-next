import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/features/reader_next/importer/models.dart';

class LegacyImportValidationService {
  const LegacyImportValidationService();

  Future<LegacyImportValidationReport> validate({
    required String legacyDbPath,
  }) async {
    final file = File(legacyDbPath);
    if (!file.existsSync()) {
      throw ArgumentError.value(legacyDbPath, 'legacyDbPath', 'File not found');
    }

    final db = sqlite.sqlite3.open(legacyDbPath);
    try {
      final diagnostics = <LegacyImportRowDiagnostic>[];
      var total = 0;
      var accepted = 0;
      final skippedByCode = <String, int>{};

      if (_tableExists(db, 'history')) {
        final historyRows = db.select(
          'SELECT id, type, time, ep, page FROM history ORDER BY rowid ASC;',
        );
        for (var i = 0; i < historyRows.length; i++) {
          total += 1;
          final row = historyRows[i];
          final code = _validateHistoryRow(row);
          if (code == null) {
            accepted += 1;
            continue;
          }
          skippedByCode[code] = (skippedByCode[code] ?? 0) + 1;
          diagnostics.add(
            LegacyImportRowDiagnostic(
              table: 'history',
              code: code,
              reason: 'History row failed validation',
              rowIndex: i,
            ),
          );
        }
      }

      if (_tableExists(db, 'comics')) {
        final comicsRows = db.select(
          'SELECT id, title, comic_type FROM comics ORDER BY rowid ASC;',
        );
        for (var i = 0; i < comicsRows.length; i++) {
          total += 1;
          final row = comicsRows[i];
          final code = _validateComicsRow(row);
          if (code == null) {
            accepted += 1;
            continue;
          }
          skippedByCode[code] = (skippedByCode[code] ?? 0) + 1;
          diagnostics.add(
            LegacyImportRowDiagnostic(
              table: 'comics',
              code: code,
              reason: 'Comics row failed validation',
              rowIndex: i,
            ),
          );
        }
      }

      final skipped = total - accepted;
      return LegacyImportValidationReport(
        legacyDbPath: legacyDbPath,
        totalRowsScanned: total,
        rowsAccepted: accepted,
        rowsSkipped: skipped,
        skippedByCode: skippedByCode,
        diagnostics: diagnostics,
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

  String? _validateHistoryRow(sqlite.Row row) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return 'LEGACY_HISTORY_MISSING_ID';

    final type = row['type'];
    if (type is! int) return 'LEGACY_HISTORY_INVALID_TYPE';

    final time = row['time'];
    if (time is! int || time < 0) return 'LEGACY_HISTORY_INVALID_TIME';

    final ep = row['ep'];
    if (ep is! int || ep < 0) return 'LEGACY_HISTORY_INVALID_EP';

    final page = row['page'];
    if (page is! int || page < 0) return 'LEGACY_HISTORY_INVALID_PAGE';

    return null;
  }

  String? _validateComicsRow(sqlite.Row row) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return 'LEGACY_COMICS_MISSING_ID';

    final title = row['title']?.toString() ?? '';
    if (title.isEmpty) return 'LEGACY_COMICS_MISSING_TITLE';

    final comicType = row['comic_type'];
    if (comicType is! int) return 'LEGACY_COMICS_INVALID_TYPE';

    return null;
  }
}
