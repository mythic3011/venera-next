class LegacyImportPreflightReport {
  const LegacyImportPreflightReport({
    required this.legacyDbPath,
    required this.runtimeDbPath,
    required this.backupPath,
    required this.runtimeBackupCreated,
    required this.legacyDbExists,
    required this.legacyTables,
    required this.legacySchemaWarnings,
  });

  final String legacyDbPath;
  final String runtimeDbPath;
  final String backupPath;
  final bool runtimeBackupCreated;
  final bool legacyDbExists;
  final List<String> legacyTables;
  final List<String> legacySchemaWarnings;
}

class LegacyImportRowDiagnostic {
  const LegacyImportRowDiagnostic({
    required this.table,
    required this.code,
    required this.reason,
    required this.rowIndex,
  });

  final String table;
  final String code;
  final String reason;
  final int rowIndex;
}

class LegacyImportValidationReport {
  const LegacyImportValidationReport({
    required this.legacyDbPath,
    required this.totalRowsScanned,
    required this.rowsAccepted,
    required this.rowsSkipped,
    required this.skippedByCode,
    required this.diagnostics,
  });

  final String legacyDbPath;
  final int totalRowsScanned;
  final int rowsAccepted;
  final int rowsSkipped;
  final Map<String, int> skippedByCode;
  final List<LegacyImportRowDiagnostic> diagnostics;
}

enum LegacyImportExecutionMode { dryRun, apply }

class LegacyImportCheckpoint {
  const LegacyImportCheckpoint({
    required this.historyRowId,
    required this.comicsRowId,
  });

  final int historyRowId;
  final int comicsRowId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'historyRowId': historyRowId,
    'comicsRowId': comicsRowId,
  };

  factory LegacyImportCheckpoint.fromJson(Map<String, dynamic> json) {
    final historyRowId = json['historyRowId'];
    final comicsRowId = json['comicsRowId'];
    return LegacyImportCheckpoint(
      historyRowId: historyRowId is int ? historyRowId : 0,
      comicsRowId: comicsRowId is int ? comicsRowId : 0,
    );
  }
}

class LegacyImportExecutionReport {
  const LegacyImportExecutionReport({
    required this.mode,
    required this.preflight,
    required this.validation,
    required this.appliedHistoryRows,
    required this.appliedComicsRows,
    required this.checkpoint,
    required this.completed,
    this.checkpointPath,
    this.dryRunArtifactPath,
    this.failureCode,
    this.failureMessage,
  });

  final LegacyImportExecutionMode mode;
  final LegacyImportPreflightReport preflight;
  final LegacyImportValidationReport validation;
  final int appliedHistoryRows;
  final int appliedComicsRows;
  final LegacyImportCheckpoint checkpoint;
  final bool completed;
  final String? checkpointPath;
  final String? dryRunArtifactPath;
  final String? failureCode;
  final String? failureMessage;
}

class LegacyHistoryImportRow {
  const LegacyHistoryImportRow({
    required this.rowId,
    required this.id,
    required this.type,
    required this.time,
    required this.ep,
    required this.page,
  });

  final int rowId;
  final String id;
  final int type;
  final int time;
  final int ep;
  final int page;
}

class LegacyComicsImportRow {
  const LegacyComicsImportRow({
    required this.rowId,
    required this.id,
    required this.title,
    required this.comicType,
  });

  final int rowId;
  final String id;
  final String title;
  final int comicType;
}
