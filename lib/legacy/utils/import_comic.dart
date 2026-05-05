import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/local.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/import_failure.dart';
import 'package:venera/utils/import_lifecycle.dart';
import 'package:venera/utils/import_sort.dart';
import 'package:venera/utils/local_import_storage.dart';
import 'package:venera/utils/translations.dart';
import 'cbz.dart';
import 'io.dart';

enum _BundleImportMode { oneComicWithChapters, separateComics }

const Set<String> _supportedImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'jpe',
};

@visibleForTesting
bool isSupportedImageExtension(String extension) {
  return _supportedImageExtensions.contains(extension.toLowerCase());
}

ImportFailure _buildPreflightConflictFailure({
  required LocalImportPreflightDecision preflight,
  required String comicTitle,
}) {
  return switch (preflight.action) {
    LocalImportPreflightAction.conflictExistingDirectory =>
      ImportFailure.destinationExists(
        comicTitle: comicTitle,
        targetDirectory: preflight.targetDirectory,
      ),
    LocalImportPreflightAction.conflictExistingCanonicalRecord =>
      ImportFailure.duplicateDetected(
        comicTitle: comicTitle,
        targetDirectory: preflight.targetDirectory,
        existingComicId: preflight.existingComicId,
      ),
    _ => throw StateError(
      'Unsupported preflight conflict action: ${preflight.action}',
    ),
  };
}

String _diagnosticMessageForImportFailure(ImportFailure failure) {
  return switch (failure.code) {
    'IMPORT_DUPLICATE_DETECTED' => 'import.local.duplicateDetected',
    'IMPORT_DESTINATION_EXISTS' => 'import.local.copyFailed',
    'IMPORT_MISSING_FILES' => 'import.local.missingFiles',
    _ => 'import.local.copyFailed',
  };
}

@visibleForTesting
Future<LocalComic?> checkSingleComicForTesting(
  Directory directory, {
  required LocalImportStoragePort localImportStorage,
  String? id,
  String? title,
  String? subtitle,
  List<String>? tags,
  DateTime? createTime,
  bool useRelativePath = false,
  bool failOnMissingFiles = false,
}) {
  return ImportComic(localImportStorage: localImportStorage)._checkSingleComic(
    directory,
    id: id,
    title: title,
    subtitle: subtitle,
    tags: tags,
    createTime: createTime,
    useRelativePath: useRelativePath,
    failOnMissingFiles: failOnMissingFiles,
  );
}

@visibleForTesting
Future<int> registerImportedComicsForTesting({
  required Map<String?, List<LocalComic>> importedComics,
  required LocalImportStoragePort localImportStorage,
  required Future<Map<String?, List<LocalComic>>> Function(
    Map<String?, List<LocalComic>> comics,
  )
  copyComicsToLocalDir,
  required void Function(String folder, FavoriteItem item) addFavoriteComic,
  required bool copy,
}) async {
  if (copy) {
    importedComics = await copyComicsToLocalDir(importedComics);
  }
  var importedCount = 0;
  for (final folder in importedComics.keys) {
    for (final comic in importedComics[folder]!) {
      final registeredComic = await localImportStorage.registerImportedComic(
        comic,
        existingComicId: comic.id == '0' ? null : comic.id,
      );
      importedCount++;
      if (folder != null) {
        addFavoriteComic(
          folder,
          FavoriteItem(
            id: registeredComic.id,
            name: registeredComic.title,
            coverPath: registeredComic.cover,
            author: registeredComic.subtitle,
            type: registeredComic.comicType,
            tags: registeredComic.tags,
            favoriteTime: registeredComic.createdAt,
          ),
        );
      }
    }
  }
  return importedCount;
}

@visibleForTesting
String? selectCoverPathForImport({
  required List<String> rootFiles,
  required Map<String, List<String>> chapterFiles,
}) {
  final sortedRootFiles = [...rootFiles]
    ..removeWhere((name) => !isSupportedImageExtension(File(name).extension))
    ..sort(naturalCompare);
  final rootCover = sortedRootFiles.firstWhereOrNull(
    (name) => File(name).name.toLowerCase().startsWith('cover'),
  );
  if (rootCover != null) {
    return rootCover;
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
      ..removeWhere((name) => !isSupportedImageExtension(File(name).extension))
      ..sort(naturalCompare);
    if (images.isNotEmpty) {
      return '$chapter/${images.first}';
    }
  }
  return null;
}

void ensureImportCopyRoot(String destinationPath) {
  Directory(destinationPath).createSync(recursive: true);
}

@visibleForTesting
void ensureImportCopyRootForTesting(String destinationPath) {
  ensureImportCopyRoot(destinationPath);
}

@visibleForTesting
bool shouldAbortImportWhenNoComics({
  required Map<String?, List<LocalComic>> imported,
  required String? selectedFolder,
}) {
  return (imported[selectedFolder] ?? const <LocalComic>[]).isEmpty;
}

class _ImportBatchResult {
  final Map<String?, List<LocalComic>> imported;
  int failed = 0;
  int skipped = 0;

  _ImportBatchResult(this.imported);
}

class _ExtractedArchive {
  final Directory cache;
  final Directory root;

  const _ExtractedArchive(this.cache, this.root);
}

class ImportComic {
  final BuildContext? uiContext;
  final String? selectedFolder;
  final bool copyToLocal;
  final LocalImportStoragePort localImportStorage;

  const ImportComic({
    this.uiContext,
    this.selectedFolder,
    this.copyToLocal = true,
    LocalImportStoragePort? localImportStorage,
  }) : localImportStorage =
           localImportStorage ?? const CanonicalLocalImportStorage();

  BuildContext? _resolveUiContext() {
    return uiContext ??
        App.rootNavigatorKey.currentState?.context ??
        App.mainNavigatorKey?.currentState?.context;
  }

  void _showMessage(String message) {
    final context = _resolveUiContext();
    if (context != null && context.mounted) {
      context.showMessage(message: message);
    }
  }

  String _resolveUiMessage(Object error, {String? fallback}) {
    if (error is ImportFailure) {
      return error.uiMessage;
    }
    return fallback ?? error.toString();
  }

  LoadingDialogController _showLoading({
    bool allowCancel = true,
    bool withProgress = false,
    String? message,
    void Function()? onCancel,
  }) {
    final context = _resolveUiContext();
    if (context == null) {
      throw Exception("UI context unavailable");
    }
    return showLoadingDialog(
      context,
      allowCancel: allowCancel,
      withProgress: withProgress,
      message: message,
      onCancel: onCancel,
    );
  }

  Future<bool> cbz() async {
    var file = await selectFile(ext: ['cbz', 'zip', '7z', 'cb7', 'pdf']);
    if (file == null) {
      return false;
    }
    var controller = _showLoading(
      allowCancel: false,
      withProgress: true,
      message: "Preparing import".tl,
    );
    final result = _ImportBatchResult({selectedFolder: []});
    try {
      final imported = await _importFile(
        File(file.path),
        result,
        onProgress: (message, progress) {
          controller.setMessage(message);
          controller.setProgress(progress);
        },
      );
      result.imported[selectedFolder]!.addAll(imported);
    } catch (e, s) {
      AppDiagnostics.error('import.comic', e, stackTrace: s);
      _showMessage(_resolveUiMessage(e));
    }
    if (shouldAbortImportWhenNoComics(
      imported: result.imported,
      selectedFolder: selectedFolder,
    )) {
      controller.close();
      return false;
    }
    controller.setMessage("Saving library".tl);
    controller.setProgress(0.98);
    final success = await registerComics(result.imported, false);
    controller.setProgress(1.0);
    controller.close();
    if (success && (result.failed > 0 || result.skipped > 0)) {
      _showMessage(
        "Import summary: ${result.imported[selectedFolder]!.length} success, ${result.failed} failed, ${result.skipped} skipped",
      );
    }
    return success;
  }

  Future<bool> multipleCbz() async {
    final selectedFiles = await selectFiles(
      ext: ['cbz', 'zip', '7z', 'cb7', 'pdf'],
    );
    List<File> files = [];
    if (selectedFiles != null) {
      files = selectedFiles.map((e) => File(e.path)).toList();
    } else {
      var picker = DirectoryPicker();
      var dir = await picker.pickDirectory(directAccess: true);
      if (dir == null) {
        return false;
      }
      files = (await dir.list().toList()).whereType<File>().toList();
    }
    files.removeWhere((e) => !isSupportedImportExtension(e.extension));
    files.sort((a, b) => naturalCompare(a.name, b.name));

    final result = _ImportBatchResult({selectedFolder: []});
    var controller = _showLoading(
      allowCancel: false,
      withProgress: true,
      message: "Preparing import".tl,
    );
    final total = files.length;
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      try {
        final base = total == 0 ? 0.0 : index / total;
        final span = total == 0 ? 1.0 : 1 / total;
        final imported = await _importFile(
          file,
          result,
          onProgress: (message, progress) {
            controller.setMessage("[${index + 1}/$total] $message");
            if (progress == null) {
              controller.setProgress(base);
            } else {
              controller.setProgress((base + progress * span).clamp(0.0, 0.99));
            }
          },
        );
        result.imported[selectedFolder]!.addAll(imported);
      } catch (e, s) {
        AppDiagnostics.error('import.comic', e, stackTrace: s);
        result.failed++;
      }
    }
    if (shouldAbortImportWhenNoComics(
      imported: result.imported,
      selectedFolder: selectedFolder,
    )) {
      controller.close();
      _showMessage("No valid comics found".tl);
      return false;
    }
    controller.setMessage("Saving library".tl);
    controller.setProgress(0.99);
    final success = await registerComics(result.imported, false);
    controller.setProgress(1.0);
    controller.close();
    if (success) {
      _showMessage(
        "Import summary: ${result.imported[selectedFolder]!.length} success, ${result.failed} failed, ${result.skipped} skipped",
      );
    }
    return success;
  }

  Future<_ExtractedArchive> _extractArchive(
    File file, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    final cache = Directory(
      FilePath.join(
        App.cachePath,
        "import_bundle_${DateTime.now().microsecondsSinceEpoch}",
      ),
    );
    cache.createSync(recursive: true);
    onProgress?.call("Extracting archive".tl, 0.08);
    await CBZ.extractArchive(file, cache);
    onProgress?.call("Scanning images".tl, 0.2);
    var root = cache;
    while (true) {
      final visible = await root
          .list()
          .where((e) => !isHiddenOrMacMetadataPath(e.path))
          .toList();
      if (visible.length == 1 && visible.first is Directory) {
        root = visible.first as Directory;
        continue;
      }
      break;
    }
    return _ExtractedArchive(cache, root);
  }

  Future<bool> _isBundleArchive(Directory root) async {
    final entities = await root
        .list()
        .where((e) => !isHiddenOrMacMetadataPath(e.path))
        .toList();
    final imageFiles = entities.whereType<File>().where((e) {
      const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'};
      return imageExtensions.contains(e.extension.toLowerCase());
    }).length;
    final childImportFiles = entities.whereType<File>().where((e) {
      return isSupportedImportExtension(e.extension);
    }).length;
    return childImportFiles >= 2 || (childImportFiles > 0 && imageFiles == 0);
  }

  Future<List<File>> _collectChildImportFiles(Directory root) async {
    final children = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (isHiddenOrMacMetadataPath(entity.path)) {
        continue;
      }
      if (isSupportedImportExtension(entity.extension)) {
        children.add(entity);
      }
    }
    children.sort((a, b) => naturalCompare(a.name, b.name));
    return children;
  }

  Future<_BundleImportMode?> _askBundleMode(
    String fileName,
    int itemCount,
  ) async {
    _BundleImportMode? mode;
    final dialogContext = _resolveUiContext();
    if (dialogContext == null) {
      return null;
    }
    await showDialog(
      context: dialogContext,
      builder: (context) {
        return ContentDialog(
          title: "Nested bundle detected".tl,
          content: Text(
            "Detected @a import items in @b".tlParams({
              "a": itemCount,
              "b": fileName,
            }),
          ).paddingHorizontal(16).paddingVertical(8),
          actions: [
            TextButton(
              onPressed: () {
                mode = _BundleImportMode.oneComicWithChapters;
                context.pop();
              },
              child: Text("One comic with chapters".tl),
            ),
            TextButton(
              onPressed: () {
                mode = _BundleImportMode.separateComics;
                context.pop();
              },
              child: Text("Separate comics".tl),
            ),
          ],
        );
      },
    );
    return mode;
  }

  Future<LocalComic?> _importBundleAsSingleComic({
    required File source,
    required Directory root,
    required _ImportBatchResult batch,
    void Function(String message, double? progress)? onProgress,
  }) async {
    final childFiles = await _collectChildImportFiles(root);
    if (childFiles.isEmpty) {
      batch.failed++;
      return null;
    }
    var title = sanitizeFileName(source.basenameWithoutExt);
    await localImportStorage.assertStorageReadyForImport(title);
    final localRootPath = await localImportStorage.requireRootPath();
    if (await localImportStorage.hasDuplicateTitle(title)) {
      title = findValidDirectoryName(localRootPath, title);
    }
    final dest = Directory(FilePath.join(localRootPath, title));
    if (dest.existsSync()) {
      await dest.deleteIgnoreError(recursive: true);
    }
    dest.createSync(recursive: true);
    final chapterMap = <String, String>{};
    final downloaded = <String>[];
    String? cover;
    try {
      for (var i = 0; i < childFiles.length; i++) {
        final child = childFiles[i];
        if (childFiles.isNotEmpty) {
          onProgress?.call(
            "Importing chapters".tl,
            0.1 + (i / childFiles.length) * 0.8,
          );
        }
        final chapterId = (i + 1).toString();
        final chapterTitle = child.basenameWithoutExt;
        final chapterDir = Directory(FilePath.join(dest.path, chapterId));
        chapterDir.createSync(recursive: true);
        List<File> pages;
        try {
          pages = await _importItemToChapter(
            child,
            chapterDir,
            onProgress: (message, progress) {
              if (childFiles.isEmpty) {
                onProgress?.call(message, progress);
                return;
              }
              if (progress == null) {
                onProgress?.call(message, 0.1 + (i / childFiles.length) * 0.8);
                return;
              }
              final overall = 0.1 + ((i + progress) / childFiles.length) * 0.8;
              onProgress?.call(message, overall.clamp(0.0, 0.95));
            },
          );
        } catch (e, s) {
          AppDiagnostics.error('import.comic', e, stackTrace: s);
          batch.failed++;
          continue;
        }
        if (pages.isEmpty) {
          batch.failed++;
          continue;
        }
        chapterMap[chapterId] = chapterTitle;
        downloaded.add(chapterId);
        if (cover == null) {
          cover = 'cover.${pages.first.extension}';
          await pages.first.copyFast(FilePath.join(dest.path, cover));
        }
      }
      if (chapterMap.isEmpty || cover == null) {
        await dest.deleteIgnoreError(recursive: true);
        return null;
      }
      onProgress?.call("Finalizing import".tl, 0.98);
      return LocalComic(
        id: '0',
        title: title,
        subtitle: '',
        tags: const [],
        directory: dest.name,
        chapters: ComicChapters(chapterMap),
        cover: cover,
        comicType: ComicType.local,
        downloadedChapters: downloaded,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      await dest.deleteIgnoreError(recursive: true);
      rethrow;
    }
  }

  Future<List<LocalComic>> _importBundleAsSeparateComics(
    Directory root,
    _ImportBatchResult batch, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    final childFiles = await _collectChildImportFiles(root);
    final comics = <LocalComic>[];
    for (var i = 0; i < childFiles.length; i++) {
      final child = childFiles[i];
      try {
        if (childFiles.isNotEmpty) {
          onProgress?.call(
            "Importing archives".tl,
            0.15 + ((i + 1) / childFiles.length) * 0.75,
          );
        }
        if (child.extension.toLowerCase() == 'pdf') {
          comics.add(await _importPdfAsComic(child));
        } else {
          comics.add(
            await CBZ.import(
              child,
              onProgress: onProgress,
              localImportStorage: localImportStorage,
            ),
          );
        }
      } catch (e, s) {
        AppDiagnostics.error('import.comic', e, stackTrace: s);
        batch.failed++;
      }
    }
    return comics;
  }

  Future<List<File>> _importItemToChapter(
    File source,
    Directory chapterDir, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    if (source.extension.toLowerCase() == 'pdf') {
      return _renderPdfToDirectory(source, chapterDir, onProgress: onProgress);
    }
    onProgress?.call("Extracting archive".tl, 0.05);
    final extracted = await _extractArchive(source, onProgress: onProgress);
    try {
      onProgress?.call("Scanning images".tl, 0.2);
      final pages = await _collectImagesRecursively(extracted.root);
      if (pages.isEmpty) {
        return <File>[];
      }
      final copied = <File>[];
      final tasks = <Map<String, String>>[];
      for (var i = 0; i < pages.length; i++) {
        final src = pages[i];
        final dstPath = FilePath.join(
          chapterDir.path,
          "${i + 1}.${src.extension}",
        );
        tasks.add({"src": src.path, "dst": dstPath});
        copied.add(File(dstPath));
      }
      await CBZ.copyFilesInBackground(
        tasks,
        onProgress: (done, total) {
          final p = 0.25 + (done / total) * 0.7;
          onProgress?.call("Copying pages".tl, p.clamp(0.0, 0.95));
        },
      );
      return copied;
    } finally {
      await extracted.cache.deleteIgnoreError(recursive: true);
    }
  }

  Future<List<File>> _collectImagesRecursively(Directory root) async {
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (isHiddenOrMacMetadataPath(entity.path)) {
        continue;
      }
      if (isSupportedImageExtension(entity.extension)) {
        files.add(entity);
      }
    }
    files.sort((a, b) => naturalCompare(a.name, b.name));
    return files;
  }

  Future<LocalComic> _importPdfAsComic(
    File source, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    final title = sanitizeFileName(source.basenameWithoutExt);
    await localImportStorage.assertStorageReadyForImport(title);
    final preflight = await localImportStorage.preflightImport(title);
    if (preflight.action ==
            LocalImportPreflightAction.conflictExistingDirectory ||
        preflight.action ==
            LocalImportPreflightAction.conflictExistingCanonicalRecord) {
      final failure = _buildPreflightConflictFailure(
        preflight: preflight,
        comicTitle: title,
      );
      AppDiagnostics.error(
        'import.local',
        failure,
        message: _diagnosticMessageForImportFailure(failure),
        data: {
          if (ImportLifecycleTrace.current != null)
            'importId': ImportLifecycleTrace.current!.id,
          ...failure.data,
        },
      );
      throw failure;
    }
    final isRepair =
        preflight.action == LocalImportPreflightAction.repairExisting;
    final dest = Directory(preflight.targetDirectory);
    if (isRepair) {
      AppDiagnostics.info(
        'import.local',
        'import.local.repairStarted',
        data: <String, Object?>{
          'comicTitle': title,
          'targetDirectory': preflight.targetDirectory,
          'existingComicId': preflight.existingComicId,
          'action': 'repairExisting',
        },
      );
      if (dest.existsSync()) {
        await dest.deleteIgnoreError(recursive: true);
      }
    }
    dest.createSync(recursive: true);
    ImportLifecycleTrace.current?.phase(
      'destination.created',
      data: {'comicTitle': title, 'targetDirectory': dest.path},
    );
    try {
      final pages = await _renderPdfToDirectory(
        source,
        dest,
        onProgress: onProgress,
      );
      ImportLifecycleTrace.current?.phase(
        'pdf.render.completed',
        data: {'comicTitle': title, 'pageCount': pages.length},
      );
      if (pages.isEmpty) {
        throw Exception("No pages found in PDF");
      }
      final cover = "cover.${pages.first.extension}";
      await pages.first.copyFast(FilePath.join(dest.path, cover));
      onProgress?.call("Finalizing import".tl, 0.98);
      ImportLifecycleTrace.current?.phase(
        'comic.materialized',
        data: {
          'comicTitle': title,
          'targetDirectory': dest.path,
          'pageCount': pages.length,
        },
      );
      final imported = LocalComic(
        id: preflight.existingComicId ?? '0',
        title: title,
        subtitle: '',
        tags: const [],
        directory: dest.name,
        chapters: null,
        cover: cover,
        comicType: ComicType.local,
        downloadedChapters: const [],
        createdAt: DateTime.now(),
      );
      if (isRepair) {
        AppDiagnostics.info(
          'import.local',
          'import.local.repairCompleted',
          data: <String, Object?>{
            'comicTitle': title,
            'targetDirectory': preflight.targetDirectory,
            'existingComicId': preflight.existingComicId,
            'action': 'repairExisting',
          },
        );
      }
      return imported;
    } catch (error, stackTrace) {
      if (isRepair) {
        AppDiagnostics.error(
          'import.local',
          error,
          stackTrace: stackTrace,
          message: 'import.local.repairFailed',
          data: <String, Object?>{
            'comicTitle': title,
            'targetDirectory': preflight.targetDirectory,
            'existingComicId': preflight.existingComicId,
            'action': 'repairExisting',
          },
        );
      }
      await dest.deleteIgnoreError(recursive: true);
      rethrow;
    }
  }

  Future<List<File>> _renderPdfToDirectory(
    File pdfFile,
    Directory outDir, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    final files = <File>[];
    onProgress?.call("Reading PDF".tl, 0.05);
    final document = await PdfDocument.openFile(pdfFile.path);
    try {
      final totalPages = document.pages.length;
      for (var i = 0; i < totalPages; i++) {
        final page = document.pages[i];
        final rendered = await page.render(
          fullWidth: page.width * 2,
          fullHeight: page.height * 2,
          backgroundColor: 0xFFFFFFFF,
        );
        if (rendered == null) {
          throw Exception("Failed to render page ${i + 1}");
        }
        try {
          final image = img.Image.fromBytes(
            width: rendered.width,
            height: rendered.height,
            bytes: rendered.pixels.buffer,
            numChannels: 4,
            order: img.ChannelOrder.bgra,
          );
          final imageFile = File(FilePath.join(outDir.path, "${i + 1}.jpg"));
          await imageFile.writeAsBytes(img.encodeJpg(image, quality: 92));
          files.add(imageFile);
          if (totalPages > 0 && (i % 2 == 0 || i == totalPages - 1)) {
            final progress = 0.1 + ((i + 1) / totalPages) * 0.85;
            onProgress?.call(
              "Rendering PDF pages".tl,
              progress.clamp(0.0, 0.96),
            );
          }
        } finally {
          rendered.dispose();
        }
      }
    } finally {
      await document.dispose();
    }
    return files;
  }

  Future<List<LocalComic>> _importFile(
    File file,
    _ImportBatchResult batch, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    final ownsLifecycle = ImportLifecycleTrace.current == null;
    final lifecycle =
        ImportLifecycleTrace.current ??
        ImportLifecycleTrace.start(
          operation: 'import.comic.file',
          sourceName: file.name,
          sourceType: file.extension.toLowerCase(),
        );
    return lifecycle.run(() async {
      try {
        onProgress?.call("Preparing import".tl, 0.02);
        lifecycle.phase('file.prepare');
        if (file.extension.toLowerCase() == 'pdf') {
          final imported = [
            await _importPdfAsComic(file, onProgress: onProgress),
          ];
          if (ownsLifecycle) {
            lifecycle.completed(data: {'importedCount': imported.length});
          }
          return imported;
        }
        final extraction = await _extractArchive(file, onProgress: onProgress);
        lifecycle.phase(
          'archive.extracted',
          data: {'cachePath': extraction.cache.path},
        );
        try {
          if (!await _isBundleArchive(extraction.root)) {
            final imported = [
              await CBZ.import(
                file,
                onProgress: onProgress,
                localImportStorage: localImportStorage,
              ),
            ];
            if (ownsLifecycle) {
              lifecycle.completed(data: {'importedCount': imported.length});
            }
            return imported;
          }
          final childFiles = await _collectChildImportFiles(extraction.root);
          lifecycle.phase(
            'bundle.detected',
            data: {'childImportFileCount': childFiles.length},
          );
          if (childFiles.isEmpty) {
            batch.failed++;
            if (ownsLifecycle) {
              lifecycle.completed(data: {'importedCount': 0, 'failed': 1});
            }
            return <LocalComic>[];
          }
          onProgress?.call("Awaiting import mode".tl, 0.12);
          final mode = await _askBundleMode(file.name, childFiles.length);
          if (mode == null) {
            batch.skipped++;
            lifecycle.phase('bundle.mode_skipped');
            if (ownsLifecycle) {
              lifecycle.completed(data: {'importedCount': 0, 'skipped': 1});
            }
            return <LocalComic>[];
          }
          lifecycle.phase('bundle.mode_selected', data: {'mode': mode.name});
          if (mode == _BundleImportMode.oneComicWithChapters) {
            final comic = await _importBundleAsSingleComic(
              source: file,
              root: extraction.root,
              batch: batch,
              onProgress: onProgress,
            );
            if (comic == null) {
              if (ownsLifecycle) {
                lifecycle.completed(data: {'importedCount': 0});
              }
              return <LocalComic>[];
            }
            if (ownsLifecycle) {
              lifecycle.completed(data: {'importedCount': 1});
            }
            return [comic];
          }
          final imported = await _importBundleAsSeparateComics(
            extraction.root,
            batch,
            onProgress: onProgress,
          );
          if (ownsLifecycle) {
            lifecycle.completed(data: {'importedCount': imported.length});
          }
          return imported;
        } finally {
          await extraction.cache.deleteIgnoreError(recursive: true);
          lifecycle.phase(
            'cache.cleaned',
            data: {'cachePath': extraction.cache.path},
          );
        }
      } catch (error, stackTrace) {
        if (ownsLifecycle) {
          lifecycle.failed(error, stackTrace: stackTrace, phase: 'file.import');
        }
        rethrow;
      }
    });
  }

  Future<bool> ehViewer() async {
    var dbFile = await selectFile(ext: ['db']);
    final picker = DirectoryPicker();
    final comicSrc = await picker.pickDirectory();
    Map<String?, List<LocalComic>> imported = {};
    if (dbFile == null || comicSrc == null) {
      return false;
    }

    bool cancelled = false;
    var controller = _showLoading(
      onCancel: () {
        cancelled = true;
      },
    );

    try {
      var db = sql.sqlite3.open(dbFile.path);

      Future<List<LocalComic>> validateComics(List<sql.Row> comics) async {
        List<LocalComic> imported = [];
        for (var comic in comics) {
          if (cancelled) {
            return imported;
          }
          var comicDir = Directory(
            FilePath.join(comicSrc.path, comic['DIRNAME'] as String),
          );
          String titleJP = comic['TITLE_JPN'] == null
              ? ""
              : comic['TITLE_JPN'] as String;
          String title = titleJP == "" ? comic['TITLE'] as String : titleJP;
          int timeStamp = comic['TIME'] as int;
          DateTime downloadTime = timeStamp != 0
              ? DateTime.fromMillisecondsSinceEpoch(timeStamp)
              : DateTime.now();
          var comicObj = await _checkSingleComic(
            comicDir,
            title: title,
            tags: [
              //1 >> x
              [
                "MISC",
                "DOUJINSHI",
                "MANGA",
                "ARTISTCG",
                "GAMECG",
                "IMAGE SET",
                "COSPLAY",
                "ASIAN PORN",
                "NON-H",
                "WESTERN",
              ][(log(comic['CATEGORY'] as int) / ln2).floor()],
            ],
            createTime: downloadTime,
          );
          if (comicObj == null) {
            continue;
          }
          imported.add(comicObj);
        }
        return imported;
      }

      var tags = <String>[""];
      tags.addAll(
        db
            .select("""
            SELECT * FROM DOWNLOAD_LABELS LB
            ORDER BY  LB.TIME DESC;
          """)
            .map((r) => r['LABEL'] as String)
            .toList(),
      );

      for (var tag in tags) {
        if (cancelled) {
          break;
        }
        var folderName = tag == '' ? '(EhViewer)Default'.tl : '(EhViewer)$tag';
        var comicList = db.select("""
              SELECT * 
              FROM DOWNLOAD_DIRNAME DN
              LEFT JOIN DOWNLOADS DL
              ON DL.GID = DN.GID
              WHERE DL.LABEL ${tag == '' ? 'IS NULL' : '= \'$tag\''} AND DL.STATE = 3
              ORDER BY DL.TIME DESC
            """).toList();

        var validComics = await validateComics(comicList);
        imported[folderName] = validComics;
        if (validComics.isNotEmpty &&
            !LocalFavoritesManager().existsFolder(folderName)) {
          LocalFavoritesManager().createFolder(folderName);
        }
      }
      db.dispose();

      //Android specific
      var cache = FilePath.join(App.cachePath, dbFile.name);
      await File(cache).deleteIgnoreError();
    } catch (e, s) {
      AppDiagnostics.error('import.comic', e, stackTrace: s);
      _showMessage(_resolveUiMessage(e));
    }
    controller.close();
    if (cancelled) return false;
    return registerComics(imported, copyToLocal);
  }

  Future<bool> directory(bool single) async {
    final picker = DirectoryPicker();
    final path = await picker.pickDirectory();
    if (path == null) {
      return false;
    }
    Map<String?, List<LocalComic>> imported = {selectedFolder: []};
    try {
      if (single) {
        var result = await _checkSingleComic(path);
        if (result != null) {
          imported[selectedFolder]!.add(result);
        } else {
          _showMessage("Invalid Comic".tl);
          return false;
        }
      } else {
        await for (var entry in path.list()) {
          if (entry is Directory) {
            var result = await _checkSingleComic(entry);
            if (result != null) {
              imported[selectedFolder]!.add(result);
            }
          }
        }
      }
    } catch (e, s) {
      AppDiagnostics.error('import.comic', e, stackTrace: s);
      _showMessage(_resolveUiMessage(e));
      return false;
    }
    return registerComics(imported, copyToLocal);
  }

  Future<bool> localDownloads() async {
    final lifecycle = ImportLifecycleTrace.start(
      operation: 'import.local_downloads',
    );
    return lifecycle.run(() async {
      LoadingDialogController? controller;
      String? rootPath;
      Directory? localDir;
      Map<String?, List<LocalComic>> imported = {null: []};
      bool cancelled = false;
      try {
        lifecycle.phase('local_downloads.root.resolve.started');
        rootPath = await localImportStorage.requireRootPath();
        localDir = Directory(rootPath);
        if (!localDir.existsSync()) {
          localDir.createSync(recursive: true);
        }
        lifecycle.phase('local_downloads.root.resolve.completed');
        controller = _showLoading(
          onCancel: () {
            cancelled = true;
          },
        );
        final rootType = FileSystemEntity.typeSync(
          rootPath,
          followLinks: false,
        );
        if (rootType != FileSystemEntityType.directory) {
          final failure = ImportFailure.missingFiles(
            comicTitle: 'local-downloads',
            targetDirectory: rootPath,
          );
          AppDiagnostics.error(
            'import.local',
            failure,
            message: 'import.local.missingFiles',
            data: {'importId': lifecycle.id, ...failure.data},
          );
          _showMessage(failure.uiMessage);
          lifecycle.completed(data: {'success': false, 'reason': failure.code});
          return false;
        }
        final candidates = localDir.listSync(
          recursive: false,
          followLinks: false,
        )..sort((a, b) => naturalCompare(a.name, b.name));
        lifecycle.phase(
          'local_downloads.scanned',
          data: {'rootPath': rootPath, 'candidateCount': candidates.length},
        );
        for (final entry in candidates) {
          if (cancelled) {
            break;
          }
          final entryType = FileSystemEntity.typeSync(
            entry.path,
            followLinks: false,
          );
          if (entryType == FileSystemEntityType.directory) {
            final directory = Directory(entry.path);
            final stat = directory.statSync();
            var result = await _checkSingleComic(
              directory,
              createTime: stat.modified,
              useRelativePath: true,
              failOnMissingFiles: true,
            );
            if (result != null) {
              imported[null]!.add(result);
              lifecycle.phase(
                'local_downloads.candidate.accepted',
                data: {
                  'comicTitle': result.title,
                  'targetDirectory': entry.path,
                },
              );
            }
          }
        }
        if (!cancelled && imported[null]!.isEmpty) {
          _showMessage("No valid comics found".tl);
        }
      } catch (e, s) {
        lifecycle.failed(e, stackTrace: s, phase: 'local_downloads.scan');
        AppDiagnostics.error('import.comic', e, stackTrace: s);
        _showMessage(_resolveUiMessage(e));
        return false;
      } finally {
        controller?.close();
      }
      if (cancelled) {
        lifecycle.completed(data: {'success': false, 'cancelled': true});
        return false;
      }
      final success = await registerComics(imported, false);
      lifecycle.completed(
        data: {
          'success': success,
          'cancelled': cancelled,
          'importedCount': imported[null]!.length,
        },
      );
      return success;
    });
  }

  //Automatically search for cover image and chapters
  Future<LocalComic?> _checkSingleComic(
    Directory directory, {
    String? id,
    String? title,
    String? subtitle,
    List<String>? tags,
    DateTime? createTime,
    bool useRelativePath = false,
    bool failOnMissingFiles = false,
  }) async {
    final entityType = FileSystemEntity.typeSync(
      directory.path,
      followLinks: false,
    );
    if (entityType != FileSystemEntityType.directory) {
      if (failOnMissingFiles) {
        throw ImportFailure.missingFiles(
          comicTitle: title ?? directory.name,
          targetDirectory: directory.path,
        );
      }
      return null;
    }
    var name = title ?? directory.name;
    await localImportStorage.assertStorageReadyForImport(name);
    if (await localImportStorage.hasDuplicateTitle(name)) {
      final failure = ImportFailure.duplicateDetected(
        comicTitle: name,
        targetDirectory: directory.path,
      );
      AppDiagnostics.error(
        'import.local',
        failure,
        message: 'import.local.duplicateDetected',
        data: failure.data,
      );
      throw failure;
    }
    bool hasChapters = false;
    final chapters = <String>[];
    final rootImageFiles = <String>[];
    final chapterImageFiles = <String, List<String>>{};
    await for (var entry in directory.list(followLinks: false)) {
      if (entry is Directory) {
        hasChapters = true;
        chapters.add(entry.name);
        chapterImageFiles[entry.name] = <String>[];
        await for (var file in entry.list(followLinks: false)) {
          if (file is Directory) {
            AppDiagnostics.info(
              'import.comic',
              'import.invalid_chapter_structure',
              data: {'chapter': entry.name},
            );
            return null;
          }
          if (file is File && isSupportedImageExtension(file.extension)) {
            chapterImageFiles[entry.name]!.add(file.name);
          }
        }
      } else if (entry is File) {
        if (isSupportedImageExtension(entry.extension)) {
          rootImageFiles.add(entry.name);
        }
      }
    }

    final hasAnyChapterImages = chapterImageFiles.values.any(
      (images) => images.isNotEmpty,
    );
    if (rootImageFiles.isEmpty && !hasAnyChapterImages) {
      return null;
    }

    naturalSortStrings(chapters);
    final coverPath = selectCoverPathForImport(
      rootFiles: rootImageFiles,
      chapterFiles: chapterImageFiles,
    );
    if (coverPath == null || coverPath.isEmpty) {
      AppDiagnostics.info(
        'import.comic',
        'import.invalid_comic_no_cover',
        data: {'title': name},
      );
      return null;
    }
    var directoryPath = useRelativePath ? directory.name : directory.path;
    return LocalComic(
      id: id ?? '0',
      title: name,
      subtitle: subtitle ?? '',
      tags: tags ?? [],
      directory: directoryPath,
      chapters: hasChapters
          ? ComicChapters(Map.fromIterables(chapters, chapters))
          : null,
      cover: coverPath,
      comicType: ComicType.local,
      downloadedChapters: chapters,
      createdAt: createTime ?? DateTime.now(),
    );
  }

  static Future<Map<String, String>> _copyDirectories(
    Map<String, dynamic> data,
  ) async {
    return overrideIO(() async {
      var toBeCopied = data['toBeCopied'] as List<String>;
      var destination = data['destination'] as String;
      ensureImportCopyRoot(destination);
      Map<String, String> result = {};
      for (var dir in toBeCopied) {
        var source = Directory(dir);
        var dest = Directory("$destination/${source.name}");
        if (dest.existsSync()) {
          throw ImportFailure.destinationExists(
            comicTitle: source.name,
            targetDirectory: dest.path,
          );
        }
        dest.parent.createSync(recursive: true);
        dest.createSync(recursive: true);
        await copyDirectory(source, dest);
        result[source.path] = dest.path;
      }
      return result;
    });
  }

  Future<Map<String?, List<LocalComic>>> _copyComicsToLocalDir(
    Map<String?, List<LocalComic>> comics,
  ) async {
    var destPath = await localImportStorage.requireRootPath();
    ImportLifecycleTrace.current?.phase(
      'copy_to_local.started',
      data: {
        'destinationRoot': destPath,
        'comicCount': comics.values.fold<int>(
          0,
          (count, list) => count + list.length,
        ),
      },
    );
    Map<String?, List<LocalComic>> result = {};
    for (var favoriteFolder in comics.keys) {
      result[favoriteFolder] = comics[favoriteFolder]!
          .where((c) => c.directory.startsWith(destPath))
          .toList();
      comics[favoriteFolder]!.removeWhere(
        (c) => c.directory.startsWith(destPath),
      );

      if (comics[favoriteFolder]!.isEmpty) {
        continue;
      }

      try {
        for (final comic in comics[favoriteFolder]!) {
          final existingDest = Directory(
            "$destPath/${Directory(comic.directory).name}",
          );
          if (existingDest.existsSync()) {
            throw ImportFailure.destinationExists(
              comicTitle: Directory(comic.directory).name,
              targetDirectory: existingDest.path,
            );
          }
        }
        // copy the comics to the local directory
        var pathMap = await compute<Map<String, dynamic>, Map<String, String>>(
          _copyDirectories,
          {
            'toBeCopied': comics[favoriteFolder]!
                .map((e) => e.directory)
                .toList(),
            'destination': destPath,
          },
        );
        //Construct a new object since LocalComic.directory is a final String
        for (var c in comics[favoriteFolder]!) {
          result[favoriteFolder]!.add(
            LocalComic(
              id: c.id,
              title: c.title,
              subtitle: c.subtitle,
              tags: c.tags,
              directory: pathMap[c.directory]!,
              chapters: c.chapters,
              cover: c.cover,
              comicType: c.comicType,
              downloadedChapters: c.downloadedChapters,
              createdAt: c.createdAt,
            ),
          );
        }
      } catch (e, s) {
        final failure = e is ImportFailure
            ? e
            : ImportFailure.copyFailed(
                'Failed to copy comics to canonical local root: $destPath',
              );
        AppDiagnostics.error(
          'import.local',
          failure,
          stackTrace: s,
          message: _diagnosticMessageForImportFailure(failure),
          data: {
            'sourcePaths': comics[favoriteFolder]!
                .map((comic) => comic.directory)
                .toList(),
            'destinationRoot': destPath,
            'errorType': e.runtimeType.toString(),
            ...failure.data,
          },
        );
        _showMessage(failure.uiMessage);
        AppDiagnostics.error('import.comic', e, stackTrace: s);
        throw failure;
      }
    }
    ImportLifecycleTrace.current?.phase(
      'copy_to_local.completed',
      data: {
        'destinationRoot': destPath,
        'comicCount': result.values.fold<int>(
          0,
          (count, list) => count + list.length,
        ),
      },
    );
    return result;
  }

  Future<bool> registerComics(
    Map<String?, List<LocalComic>> importedComics,
    bool copy,
  ) async {
    final ownsLifecycle = ImportLifecycleTrace.current == null;
    final lifecycle =
        ImportLifecycleTrace.current ??
        ImportLifecycleTrace.start(
          operation: 'import.register_comics',
          data: {
            'copyToLocal': copy,
            'comicCount': importedComics.values.fold<int>(
              0,
              (count, list) => count + list.length,
            ),
          },
        );
    try {
      final importedCount = await lifecycle.run(() {
        lifecycle.phase('register.started');
        return registerImportedComicsForTesting(
          importedComics: importedComics,
          localImportStorage: localImportStorage,
          copyComicsToLocalDir: _copyComicsToLocalDir,
          addFavoriteComic: (folder, item) {
            LocalFavoritesManager().addComic(folder, item);
          },
          copy: copy,
        );
      });
      if (ownsLifecycle) {
        lifecycle.completed(data: {'importedCount': importedCount});
      } else {
        lifecycle.phase(
          'register.completed',
          data: {'importedCount': importedCount},
        );
      }
      _showMessage("Imported @a comics".tlParams({'a': importedCount}));
    } catch (e, s) {
      _showMessage(
        _resolveUiMessage(e, fallback: "Failed to register comics".tl),
      );
      if (ownsLifecycle) {
        lifecycle.failed(e, stackTrace: s, phase: 'register');
      } else {
        lifecycle.phase(
          'register.failed',
          data: {'errorType': e.runtimeType.toString()},
        );
      }
      AppDiagnostics.error('import.comic', e, stackTrace: s);
      return false;
    }
    return true;
  }
}
