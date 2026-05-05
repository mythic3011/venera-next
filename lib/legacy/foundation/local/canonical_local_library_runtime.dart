import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:venera/features/sources/comic_source/comic_source.dart'
    show ComicChapters;
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/local/local_library_file_probe.dart';
import 'package:venera/foundation/sources/identity/constants.dart';
import 'package:venera/utils/import_sort.dart';
import 'package:venera/utils/local_import_storage.dart';

class CanonicalLocalLibraryRuntimeService {
  CanonicalLocalLibraryRuntimeService({
    required this.store,
    Future<String> Function()? resolveRootPath,
    Future<LocalComic> Function(LocalComic comic, {String? existingComicId})?
    registerImportedComic,
  }) : _resolveRootPath =
           resolveRootPath ?? const CanonicalLocalImportStorage().requireRootPath,
       _registerImportedComic =
           registerImportedComic ??
           _defaultRegisterImportedComic;

  final UnifiedComicsStore store;
  final Future<String> Function() _resolveRootPath;
  final Future<LocalComic> Function(
    LocalComic comic, {
    String? existingComicId,
  })
  _registerImportedComic;
  final LocalLibraryFileProbe _fileProbe = const LocalLibraryFileProbe();

  Future<String> requireRootPath() => _resolveRootPath();

  static Future<LocalComic> _defaultRegisterImportedComic(
    LocalComic comic, {
    String? existingComicId,
  }) {
    return const CanonicalLocalImportStorage().registerImportedComic(
      comic,
      existingComicId: existingComicId,
    );
  }

  Future<List<LocalComic>> loadAvailableComics({
    bool reconcile = false,
  }) async {
    if (reconcile) {
      await recheck();
    }
    final browseRecords = await store.loadLocalLibraryBrowseRecords();
    final primaryItems = await store.loadAllLocalLibraryItems();
    final primaryByComicId = <String, LocalLibraryItemRecord>{};
    for (final item in primaryItems) {
      primaryByComicId.putIfAbsent(item.comicId, () => item);
    }

    final comics = <LocalComic>[];
    for (final browse in browseRecords) {
      final primary = primaryByComicId[browse.comicId];
      final storedDirectoryName = primary == null
          ? null
          : _directoryNameFromPath(primary.localRootPath);
      if (primary == null) {
        _emitMissingCanonicalItem(
          comicId: browse.comicId,
          storedDirectoryName: storedDirectoryName,
          action: 'hide',
        );
        continue;
      }
      final probeResult = _probePrimaryItem(primary);
      if (!probeResult.isAvailable) {
        if (probeResult.status == LocalLibraryFileStatus.missingDirectory ||
            probeResult.status == LocalLibraryFileStatus.notDirectory ||
            probeResult.status == LocalLibraryFileStatus.unsafePath) {
          _emitMissingCanonicalItem(
            comicId: browse.comicId,
            storedDirectoryName: storedDirectoryName,
            action: 'hide',
          );
        } else {
          _emitMissingFiles(
            comicId: browse.comicId,
            storedDirectoryName: storedDirectoryName,
            action: 'hide',
            status: probeResult.status.name,
          );
        }
        continue;
      }
      final comic = _buildRuntimeComic(
        directory: Directory(primary.localRootPath),
        comicId: browse.comicId,
        title: browse.title,
        tags: [...browse.userTags, ...browse.sourceTags],
        createdAt: _parseTimestamp(primary.importedAt) ?? _parseTimestamp(browse.updatedAt),
      );
      if (comic == null) {
        _emitMissingFiles(
          comicId: browse.comicId,
          storedDirectoryName: storedDirectoryName,
          action: 'hide',
          status: LocalLibraryFileStatus.noReadablePages.name,
        );
        continue;
      }
      comics.add(comic);
    }
    return comics;
  }

  Future<LocalComic?> loadComicById(
    String comicId, {
    bool reconcile = false,
  }) async {
    final comics = await loadAvailableComics(reconcile: reconcile);
    for (final comic in comics) {
      if (comic.id == comicId) {
        return comic;
      }
    }
    return null;
  }

  Future<int> recheck() async {
    final rootPath = await _resolveRootPath();
    final rootDirectory = Directory(rootPath);
    rootDirectory.createSync(recursive: true);

    final browseRecords = await store.loadLocalLibraryBrowseRecords();
    final primaryItems = await store.loadAllLocalLibraryItems();
    final browseByComicId = {
      for (final record in browseRecords) record.comicId: record,
    };
    final primaryByComicId = <String, LocalLibraryItemRecord>{};
    final itemsByDirectoryName = <String, List<LocalLibraryItemRecord>>{};
    final itemsByPath = <String, LocalLibraryItemRecord>{};
    final titleToComicIds = <String, List<String>>{};
    for (final browse in browseRecords) {
      titleToComicIds.putIfAbsent(browse.normalizedTitle, () => <String>[]).add(
        browse.comicId,
      );
    }
    for (final item in primaryItems) {
      primaryByComicId.putIfAbsent(item.comicId, () => item);
      final normalizedPath = p.normalize(item.localRootPath.trim());
      itemsByPath[normalizedPath] = item;
      final directoryName = _directoryNameFromPath(item.localRootPath);
      if (directoryName != null) {
        itemsByDirectoryName.putIfAbsent(directoryName, () => <LocalLibraryItemRecord>[]).add(item);
      }
    }

    final seenComicIds = <String>{};
    var createdCount = 0;
    final directories = rootDirectory
        .listSync(recursive: false, followLinks: false)
        .whereType<Directory>()
        .toList(growable: false)
      ..sort(
        (left, right) =>
            naturalCompare(_entityName(left.path), _entityName(right.path)),
      );

    for (final directory in directories) {
      final discoveredDirectoryName = _entityName(directory.path);
      final discovered = _buildRuntimeComic(
        directory: directory,
        comicId: '0',
        title: discoveredDirectoryName,
        tags: const <String>[],
        createdAt: directory.statSync().modified,
      );
      if (discovered == null) {
        _emitMissingFiles(
          comicId: discoveredDirectoryName,
          discoveredDirectoryName: discoveredDirectoryName,
          action: 'hide',
          status: LocalLibraryFileStatus.noReadablePages.name,
        );
        continue;
      }

      final normalizedPath = p.normalize(directory.path);
      final directItem = itemsByPath[normalizedPath];
      final directoryCandidates =
          itemsByDirectoryName[discoveredDirectoryName]
              ?.map((item) => item.comicId)
              .toSet() ??
          const <String>{};
      final titleKey = _normalizeMatchKey(discoveredDirectoryName);
      final titleCandidates =
          titleToComicIds[titleKey]?.toSet() ?? const <String>{};

      String? matchedComicId;
      String action;
      if (directItem != null) {
        matchedComicId = directItem.comicId;
        action = 'sync';
      } else if (directoryCandidates.length == 1) {
        matchedComicId = directoryCandidates.single;
        action = 'relink_directory';
      } else if (directoryCandidates.isEmpty && titleCandidates.length == 1) {
        matchedComicId = titleCandidates.single;
        action = 'relink_title';
      } else if (directoryCandidates.isEmpty && titleCandidates.isEmpty) {
        final created = await _registerImportedComic(
          _withComicIdentity(
            discovered,
            comicId: discovered.id,
            title: discoveredDirectoryName,
          ),
        );
        createdCount++;
        seenComicIds.add(created.id);
        AppDiagnostics.info(
          'local.library',
          'local.library.canonicalFolderDiscovered',
          data: <String, Object?>{
            'comicId': created.id,
            'sourceKey': localSourceKey,
            'discoveredDirectoryName': discoveredDirectoryName,
            'action': 'create',
          },
        );
        continue;
      } else {
        _emitMissingCanonicalItem(
          comicId: discoveredDirectoryName,
          discoveredDirectoryName: discoveredDirectoryName,
          action: 'hide',
        );
        continue;
      }

      final browse = browseByComicId[matchedComicId]!;
      final synced = await _registerImportedComic(
        _withComicIdentity(
          discovered,
          comicId: matchedComicId,
          title: browse.title,
          createdAt:
              _parseTimestamp(primaryByComicId[matchedComicId]?.importedAt) ??
              discovered.createdAt,
        ),
        existingComicId: matchedComicId,
      );
      seenComicIds.add(synced.id);
      if (action != 'sync') {
        AppDiagnostics.info(
          'local.library',
          'local.library.canonicalRelinked',
          data: <String, Object?>{
            'comicId': synced.id,
            'sourceKey': localSourceKey,
            'storedDirectoryName':
                _directoryNameFromPath(
                  primaryByComicId[matchedComicId]?.localRootPath,
                ),
            'discoveredDirectoryName': discoveredDirectoryName,
            'action': action,
          },
        );
      }
    }

    for (final item in primaryItems) {
      if (seenComicIds.contains(item.comicId)) {
        continue;
      }
      final probeResult = _probePrimaryItem(item);
      if (probeResult.isAvailable) {
        continue;
      }
      _emitMissingCanonicalItem(
        comicId: item.comicId,
        storedDirectoryName: _directoryNameFromPath(item.localRootPath),
        action: 'hide',
      );
    }

    return createdCount;
  }

  LocalLibraryFileProbeResult _probePrimaryItem(LocalLibraryItemRecord item) {
    final storedDirectoryName =
        _directoryNameFromPath(item.localRootPath) ?? item.localRootPath;
    return _fileProbe.probe(
      canonicalRootPath: p.dirname(item.localRootPath),
      comicDirectoryName: storedDirectoryName,
      preferredExpectedDirectory: item.localRootPath,
    );
  }

  LocalComic? _buildRuntimeComic({
    required Directory directory,
    required String comicId,
    required String title,
    required List<String> tags,
    DateTime? createdAt,
  }) {
    final rootFiles = directory
        .listSync(recursive: false, followLinks: false)
        .whereType<File>()
        .where((file) => _isSupportedImageExtension(_fileExtension(file.path)))
        .map((file) => _entityName(file.path))
        .toList(growable: false);
    final chapterDirectories = directory
        .listSync(recursive: false, followLinks: false)
        .whereType<Directory>()
        .toList(growable: false);
    final chapterNames = chapterDirectories
        .map((child) => _entityName(child.path))
        .toList(growable: true);
    final chapterFiles = <String, List<String>>{};
    for (final child in chapterDirectories) {
      final files = child
          .listSync(recursive: false, followLinks: false)
          .whereType<File>()
          .where((file) => _isSupportedImageExtension(_fileExtension(file.path)))
          .map((file) => _entityName(file.path))
          .toList(growable: false);
      chapterFiles[_entityName(child.path)] = files;
    }
    final hasAnyChapterImages = chapterFiles.values.any(
      (files) => files.isNotEmpty,
    );
    if (rootFiles.isEmpty && !hasAnyChapterImages) {
      return null;
    }
    chapterNames.sort(naturalCompare);
    final coverPath = _selectCoverPathForImport(
      rootFiles: rootFiles,
      chapterFiles: chapterFiles,
    );
    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }
    return LocalComic(
      id: comicId,
      title: title,
      subtitle: '',
      tags: tags,
      directory: directory.path,
      chapters: chapterNames.isEmpty
          ? null
          : ComicChapters(Map.fromIterables(chapterNames, chapterNames)),
      cover: coverPath,
      comicType: ComicType.local,
      downloadedChapters: chapterNames,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  LocalComic _withComicIdentity(
    LocalComic comic, {
    required String comicId,
    required String title,
    DateTime? createdAt,
  }) {
    return LocalComic(
      id: comicId,
      title: title,
      subtitle: comic.subtitle,
      tags: comic.tags,
      directory: comic.directory,
      chapters: comic.chapters,
      cover: comic.cover,
      comicType: comic.comicType,
      downloadedChapters: comic.downloadedChapters,
      createdAt: createdAt ?? comic.createdAt,
    );
  }

  DateTime? _parseTimestamp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  String _normalizeMatchKey(String value) {
    return value.trim().toLowerCase();
  }

  String? _directoryNameFromPath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    return p.basename(p.normalize(path.trim()));
  }

  String _entityName(String path) {
    return p.basename(path);
  }

  String _fileExtension(String path) {
    return p.extension(path).replaceFirst('.', '');
  }

  bool _isSupportedImageExtension(String extension) {
    const supported = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'};
    return supported.contains(extension.toLowerCase());
  }

  String? _selectCoverPathForImport({
    required List<String> rootFiles,
    required Map<String, List<String>> chapterFiles,
  }) {
    final sortedRootFiles = [...rootFiles]
      ..removeWhere((name) => !_isSupportedImageExtension(_fileExtension(name)))
      ..sort(naturalCompare);
    for (final name in sortedRootFiles) {
      if (p.basename(name).toLowerCase().startsWith('cover')) {
        return name;
      }
    }
    if (sortedRootFiles.isNotEmpty) {
      return sortedRootFiles.first;
    }
    if (chapterFiles.isEmpty) {
      return null;
    }
    final sortedChapterNames = chapterFiles.keys.toList()..sort(naturalCompare);
    for (final chapter in sortedChapterNames) {
      final images = [...(chapterFiles[chapter] ?? const <String>[])]
        ..removeWhere((name) => !_isSupportedImageExtension(_fileExtension(name)))
        ..sort(naturalCompare);
      if (images.isNotEmpty) {
        return '$chapter/${images.first}';
      }
    }
    return null;
  }

  void _emitMissingCanonicalItem({
    required String comicId,
    String? storedDirectoryName,
    String? discoveredDirectoryName,
    required String action,
  }) {
    AppDiagnostics.info(
      'local.library',
      'local.library.missingCanonicalItem',
      data: <String, Object?>{
        'comicId': comicId,
        'sourceKey': localSourceKey,
        'storedDirectoryName': storedDirectoryName,
        'discoveredDirectoryName': discoveredDirectoryName,
        'action': action,
      },
    );
  }

  void _emitMissingFiles({
    required String comicId,
    String? storedDirectoryName,
    String? discoveredDirectoryName,
    required String action,
    required String status,
  }) {
    AppDiagnostics.warn(
      'local.library',
      'local.library.missingFiles',
      data: <String, Object?>{
        'comicId': comicId,
        'sourceKey': localSourceKey,
        'storedDirectoryName': storedDirectoryName,
        'discoveredDirectoryName': discoveredDirectoryName,
        'action': action,
        'status': status,
      },
    );
  }
}
