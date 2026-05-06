import 'dart:io';

class DirectJsStagedSourceWriterException implements Exception {
  const DirectJsStagedSourceWriterException(this.message);

  final String message;

  @override
  String toString() => 'DirectJsStagedSourceWriterException: $message';
}

class DirectJsStagedSourceWriter {
  DirectJsStagedSourceWriter({
    required this.activeDir,
    required this.stagedDir,
  });

  final Directory activeDir;
  final Directory stagedDir;

  Future<File> createStagedFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    _validateFileName(fileName);
    _assertDirectoryRootContainment(
      dir: stagedDir,
      rootLabel: 'stagedDir',
      rootCandidate: stagedDir,
    );
    final stagedFile = File(
      '${stagedDir.path}/${DateTime.now().microsecondsSinceEpoch}_$fileName',
    );
    _assertFileContained(
      file: stagedFile,
      root: stagedDir,
      rootLabel: 'stagedDir',
    );
    await stagedFile.create(recursive: true);
    await stagedFile.writeAsBytes(bytes, flush: true);
    return stagedFile;
  }

  Future<File?> stageValidateAndCommit({
    required String fileName,
    required List<int> bytes,
    required Future<bool> Function(File stagedFile) validateStaged,
  }) async {
    final stagedFile = await createStagedFile(fileName: fileName, bytes: bytes);
    try {
      final isValid = await validateStaged(stagedFile);
      if (!isValid) {
        await _safeDelete(stagedFile);
        return null;
      }
      return commitStagedFile(stagedFile, activeFileName: fileName);
    } catch (_) {
      await _safeDelete(stagedFile);
      rethrow;
    }
  }

  Future<File> commitStagedFile(
    File stagedFile, {
    required String activeFileName,
  }) async {
    _validateFileName(activeFileName);
    _assertDirectoryRootContainment(
      dir: activeDir,
      rootLabel: 'activeDir',
      rootCandidate: activeDir,
    );
    _assertFileContained(file: stagedFile, root: stagedDir, rootLabel: 'stagedDir');
    final target = File('${activeDir.path}/$activeFileName');
    _assertFileContained(file: target, root: activeDir, rootLabel: 'activeDir');
    if (await target.exists()) {
      throw const DirectJsStagedSourceWriterException(
        'Active target already exists; overwrite is not allowed',
      );
    }
    await target.parent.create(recursive: true);
    await stagedFile.rename(target.path);
    return target;
  }

  Future<void> _safeDelete(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _validateFileName(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty ||
        trimmed.contains('..') ||
        trimmed.contains('/') ||
        trimmed.contains('\\')) {
      throw const DirectJsStagedSourceWriterException(
        'Invalid file name; path traversal is not allowed',
      );
    }
  }

  void _assertDirectoryRootContainment({
    required Directory dir,
    required String rootLabel,
    required Directory rootCandidate,
  }) {
    final root = rootCandidate.absolute.path;
    final candidate = dir.absolute.path;
    if (!_isSameOrUnder(candidate, root)) {
      throw DirectJsStagedSourceWriterException(
        '$rootLabel must be a canonical root-contained path',
      );
    }
  }

  void _assertFileContained({
    required File file,
    required Directory root,
    required String rootLabel,
  }) {
    final rootPath = root.absolute.path;
    final filePath = file.absolute.path;
    if (!_isSameOrUnder(filePath, rootPath)) {
      throw DirectJsStagedSourceWriterException(
        '$rootLabel containment check failed for file path',
      );
    }
  }

  bool _isSameOrUnder(String candidate, String root) {
    final normalizedRoot = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    return candidate == root || candidate.startsWith(normalizedRoot);
  }
}
