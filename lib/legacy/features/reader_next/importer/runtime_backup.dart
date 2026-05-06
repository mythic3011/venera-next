import 'dart:io';

class RuntimeDatabaseBackupService {
  const RuntimeDatabaseBackupService();

  Future<String> backup({
    required String runtimeDbPath,
    required String backupDirectoryPath,
    DateTime? now,
  }) async {
    final runtimeFile = File(runtimeDbPath);
    if (!runtimeFile.existsSync()) {
      throw ArgumentError.value(
        runtimeDbPath,
        'runtimeDbPath',
        'Runtime database file not found',
      );
    }
    final backupDir = Directory(backupDirectoryPath);
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    final timestamp = (now ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-');
    final backupPath = '${backupDir.path}/venera-runtime-backup-$timestamp.db';
    await runtimeFile.copy(backupPath);
    return backupPath;
  }
}
