import 'dart:io';

import 'package:path/path.dart' as p;

const Set<String> _probeImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'jpe',
};

enum LocalLibraryFileStatus {
  available,
  missingDirectory,
  notDirectory,
  emptyDirectory,
  noReadablePages,
  unsafePath,
}

class LocalLibraryFileProbeResult {
  const LocalLibraryFileProbeResult({
    required this.status,
    required this.expectedDirectory,
  });

  final LocalLibraryFileStatus status;
  final String expectedDirectory;

  bool get isAvailable => status == LocalLibraryFileStatus.available;

  bool get isCleanupCandidate => switch (status) {
    LocalLibraryFileStatus.missingDirectory ||
    LocalLibraryFileStatus.notDirectory ||
    LocalLibraryFileStatus.emptyDirectory ||
    LocalLibraryFileStatus.noReadablePages => true,
    LocalLibraryFileStatus.available ||
    LocalLibraryFileStatus.unsafePath => false,
  };
}

class LocalLibraryFileProbe {
  const LocalLibraryFileProbe();

  LocalLibraryFileProbeResult probe({
    required String canonicalRootPath,
    required String comicDirectoryName,
    String? preferredExpectedDirectory,
  }) {
    final root = p.normalize(canonicalRootPath.trim());
    if (root.isEmpty) {
      return const LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.unsafePath,
        expectedDirectory: '',
      );
    }

    if (p.isAbsolute(comicDirectoryName)) {
      final normalizedAbsolute = p.normalize(comicDirectoryName);
      return LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.unsafePath,
        expectedDirectory: normalizedAbsolute,
      );
    }

    final normalizedDirectoryName = p.normalize(comicDirectoryName.trim());
    if (normalizedDirectoryName.isEmpty ||
        normalizedDirectoryName == '.' ||
        normalizedDirectoryName.startsWith('..') ||
        normalizedDirectoryName.contains('/../') ||
        normalizedDirectoryName.contains('\\..\\')) {
      return LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.unsafePath,
        expectedDirectory: p.join(root, normalizedDirectoryName),
      );
    }

    final expectedDirectory = p.normalize(
      preferredExpectedDirectory == null || preferredExpectedDirectory.isEmpty
          ? p.join(root, normalizedDirectoryName)
          : preferredExpectedDirectory,
    );

    final isWithinRoot =
        p.equals(expectedDirectory, root) ||
        p.isWithin(root, expectedDirectory);
    if (!isWithinRoot) {
      return LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.unsafePath,
        expectedDirectory: expectedDirectory,
      );
    }

    final entityType = FileSystemEntity.typeSync(
      expectedDirectory,
      followLinks: false,
    );

    if (entityType == FileSystemEntityType.notFound) {
      return LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.missingDirectory,
        expectedDirectory: expectedDirectory,
      );
    }

    if (entityType != FileSystemEntityType.directory) {
      return LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.notDirectory,
        expectedDirectory: expectedDirectory,
      );
    }

    final directory = Directory(expectedDirectory);
    final rootImages = _listImageFiles(directory);
    final childDirectories = _listChildDirectories(directory);

    if (rootImages.isNotEmpty) {
      return LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.available,
        expectedDirectory: expectedDirectory,
      );
    }

    if (childDirectories.isEmpty) {
      return LocalLibraryFileProbeResult(
        status: LocalLibraryFileStatus.emptyDirectory,
        expectedDirectory: expectedDirectory,
      );
    }

    for (final child in childDirectories) {
      final chapterImages = _listImageFiles(child);
      if (chapterImages.isNotEmpty) {
        return LocalLibraryFileProbeResult(
          status: LocalLibraryFileStatus.available,
          expectedDirectory: expectedDirectory,
        );
      }
    }

    return LocalLibraryFileProbeResult(
      status: LocalLibraryFileStatus.noReadablePages,
      expectedDirectory: expectedDirectory,
    );
  }

  List<FileSystemEntity> _safeList(Directory directory) {
    try {
      return directory.listSync(recursive: false, followLinks: false);
    } catch (_) {
      return const <FileSystemEntity>[];
    }
  }

  List<Directory> _listChildDirectories(Directory directory) {
    return _safeList(directory).whereType<Directory>().toList(growable: false);
  }

  List<File> _listImageFiles(Directory directory) {
    return _safeList(directory)
        .whereType<File>()
        .where((file) {
          final extension = p
              .extension(file.path)
              .replaceFirst('.', '')
              .toLowerCase();
          return _probeImageExtensions.contains(extension);
        })
        .toList(growable: false);
  }
}
