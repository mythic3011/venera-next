import 'package:venera/features/reader_next/importer/legacy_import_execution.dart';
import 'package:venera/features/reader_next/importer/models.dart';

class LegacyImporterRunRequest {
  const LegacyImporterRunRequest({
    required this.mode,
    required this.legacyDbPath,
    required this.runtimeDbPath,
    required this.backupDirectoryPath,
    required this.checkpointDirectoryPath,
    this.now,
  });

  final LegacyImportExecutionMode mode;
  final String legacyDbPath;
  final String runtimeDbPath;
  final String backupDirectoryPath;
  final String checkpointDirectoryPath;
  final DateTime? now;
}

/// Importer-only orchestration entrypoint.
/// This must be invoked explicitly by import tooling and never by reader runtime.
class LegacyImporterCoordinator {
  const LegacyImporterCoordinator({
    required LegacyImportExecutionService executionService,
  }) : _executionService = executionService;

  final LegacyImportExecutionService _executionService;

  Future<LegacyImportExecutionReport> run(LegacyImporterRunRequest request) {
    return _executionService.run(
      mode: request.mode,
      legacyDbPath: request.legacyDbPath,
      runtimeDbPath: request.runtimeDbPath,
      backupDirectoryPath: request.backupDirectoryPath,
      checkpointDirectoryPath: request.checkpointDirectoryPath,
      now: request.now,
    );
  }
}
