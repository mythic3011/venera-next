import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/log.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/import_sort.dart';
import 'package:venera/utils/translations.dart';
import 'cbz.dart';
import 'io.dart';

enum _BundleImportMode { oneComicWithChapters, separateComics }

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
  final String? selectedFolder;
  final bool copyToLocal;

  const ImportComic({this.selectedFolder, this.copyToLocal = true});

  Future<bool> cbz() async {
    var file = await selectFile(ext: ['cbz', 'zip', '7z', 'cb7', 'pdf']);
    if (file == null) {
      return false;
    }
    var controller = showLoadingDialog(
      App.rootContext,
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
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
    }
    if (result.imported[selectedFolder]!.isEmpty) {
      controller.close();
      return false;
    }
    controller.setMessage("Saving library".tl);
    controller.setProgress(0.98);
    final success = await registerComics(result.imported, false);
    controller.setProgress(1.0);
    controller.close();
    if (success && (result.failed > 0 || result.skipped > 0)) {
      App.rootContext.showMessage(
        message:
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
    var controller = showLoadingDialog(
      App.rootContext,
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
        Log.error("Import Comic", e.toString(), s);
        result.failed++;
      }
    }
    if (result.imported[selectedFolder]!.isEmpty) {
      App.rootContext.showMessage(message: "No valid comics found".tl);
    }
    controller.setMessage("Saving library".tl);
    controller.setProgress(0.99);
    final success = await registerComics(result.imported, false);
    controller.setProgress(1.0);
    controller.close();
    if (success) {
      App.rootContext.showMessage(
        message:
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
    await showDialog(
      context: App.rootContext,
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
    var existed = LocalManager().findByName(title);
    if (existed != null) {
      title = findValidDirectoryName(LocalManager().path, title);
    }
    final dest = Directory(FilePath.join(LocalManager().path, title));
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
          Log.error("Import Comic", e.toString(), s);
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
          comics.add(await CBZ.import(child, onProgress: onProgress));
        }
      } catch (e, s) {
        Log.error("Import Comic", e.toString(), s);
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
    const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'};
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (isHiddenOrMacMetadataPath(entity.path)) {
        continue;
      }
      if (imageExtensions.contains(entity.extension.toLowerCase())) {
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
    if (LocalManager().findByName(title) != null) {
      throw Exception("Comic with name $title already exists");
    }
    final dest = Directory(FilePath.join(LocalManager().path, title));
    if (dest.existsSync()) {
      await dest.deleteIgnoreError(recursive: true);
    }
    dest.createSync(recursive: true);
    try {
      final pages = await _renderPdfToDirectory(
        source,
        dest,
        onProgress: onProgress,
      );
      if (pages.isEmpty) {
        throw Exception("No pages found in PDF");
      }
      final cover = "cover.${pages.first.extension}";
      await pages.first.copyFast(FilePath.join(dest.path, cover));
      onProgress?.call("Finalizing import".tl, 0.98);
      return LocalComic(
        id: '0',
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
    } catch (_) {
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
    onProgress?.call("Preparing import".tl, 0.02);
    if (file.extension.toLowerCase() == 'pdf') {
      return [await _importPdfAsComic(file, onProgress: onProgress)];
    }
    final extraction = await _extractArchive(file, onProgress: onProgress);
    try {
      if (!await _isBundleArchive(extraction.root)) {
        return [await CBZ.import(file, onProgress: onProgress)];
      }
      final childFiles = await _collectChildImportFiles(extraction.root);
      if (childFiles.isEmpty) {
        batch.failed++;
        return <LocalComic>[];
      }
      onProgress?.call("Awaiting import mode".tl, 0.12);
      final mode = await _askBundleMode(file.name, childFiles.length);
      if (mode == null) {
        batch.skipped++;
        return <LocalComic>[];
      }
      if (mode == _BundleImportMode.oneComicWithChapters) {
        final comic = await _importBundleAsSingleComic(
          source: file,
          root: extraction.root,
          batch: batch,
          onProgress: onProgress,
        );
        if (comic == null) {
          return <LocalComic>[];
        }
        return [comic];
      }
      return _importBundleAsSeparateComics(
        extraction.root,
        batch,
        onProgress: onProgress,
      );
    } finally {
      await extraction.cache.deleteIgnoreError(recursive: true);
    }
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
    var controller = showLoadingDialog(
      App.rootContext,
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
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
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
          App.rootContext.showMessage(message: "Invalid Comic".tl);
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
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
    }
    return registerComics(imported, copyToLocal);
  }

  Future<bool> localDownloads() async {
    var localDir = LocalManager().directory;
    Map<String?, List<LocalComic>> imported = {null: []};
    bool cancelled = false;
    var controller = showLoadingDialog(
      App.rootContext,
      onCancel: () {
        cancelled = true;
      },
    );
    try {
      if (!await localDir.exists()) {
        App.rootContext.showMessage(message: "Local path not found".tl);
        controller.close();
        return false;
      }
      await for (var entry in localDir.list()) {
        if (cancelled) {
          break;
        }
        if (entry is Directory) {
          var stat = await entry.stat();
          var result = await _checkSingleComic(
            entry,
            createTime: stat.modified,
            useRelativePath: true,
          );
          if (result != null) {
            imported[null]!.add(result);
          }
        }
      }
      if (!cancelled && imported[null]!.isEmpty) {
        App.rootContext.showMessage(message: "No valid comics found".tl);
      }
    } catch (e, s) {
      Log.error("Import Comic", e.toString(), s);
      App.rootContext.showMessage(message: e.toString());
    }
    controller.close();
    if (cancelled) return false;
    return registerComics(imported, false);
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
  }) async {
    if (!(await directory.exists())) return null;
    var name = title ?? directory.name;
    if (LocalManager().findByName(name) != null) {
      Log.info("Import Comic", "Comic already exists: $name");
      return null;
    }
    bool hasChapters = false;
    var chapters = <String>[];
    var coverPath = ''; // relative path to the cover image
    var fileList = <String>[];
    await for (var entry in directory.list()) {
      if (entry is Directory) {
        hasChapters = true;
        chapters.add(entry.name);
        await for (var file in entry.list()) {
          if (file is Directory) {
            Log.info(
              "Import Comic",
              "Invalid Chapter: ${entry.name}\nA directory is found in the chapter directory.",
            );
            return null;
          }
        }
      } else if (entry is File) {
        const imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'];
        if (imageExtensions.contains(entry.extension)) {
          fileList.add(entry.name);
        }
      }
    }

    if (fileList.isEmpty) {
      return null;
    }

    naturalSortStrings(fileList);
    coverPath =
        fileList.firstWhereOrNull((l) => l.startsWith('cover')) ??
        fileList.first;

    naturalSortStrings(chapters);
    if (hasChapters && coverPath == '') {
      // use the first image in the first chapter as the cover
      var firstChapter = Directory('${directory.path}/${chapters.first}');
      await for (var entry in firstChapter.list()) {
        if (entry is File) {
          coverPath = entry.name;
          break;
        }
      }
    }
    if (coverPath == '') {
      Log.info("Import Comic", "Invalid Comic: $name\nNo cover image found.");
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
      Map<String, String> result = {};
      for (var dir in toBeCopied) {
        var source = Directory(dir);
        var dest = Directory("$destination/${source.name}");
        if (dest.existsSync()) {
          // The destination directory already exists, and it is not managed by the app.
          // Rename the old directory to avoid conflicts.
          Log.info(
            "Import Comic",
            "Directory already exists: ${source.name}\nRenaming the old directory.",
          );
          dest.renameSync(
            findValidDirectoryName(dest.parent.path, "${dest.path}_old"),
          );
        }
        dest.createSync();
        await copyDirectory(source, dest);
        result[source.path] = dest.path;
      }
      return result;
    });
  }

  Future<Map<String?, List<LocalComic>>> _copyComicsToLocalDir(
    Map<String?, List<LocalComic>> comics,
  ) async {
    var destPath = LocalManager().path;
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
        App.rootContext.showMessage(message: "Failed to copy comics".tl);
        Log.error("Import Comic", e.toString(), s);
        return result;
      }
    }
    return result;
  }

  Future<bool> registerComics(
    Map<String?, List<LocalComic>> importedComics,
    bool copy,
  ) async {
    try {
      if (copy) {
        importedComics = await _copyComicsToLocalDir(importedComics);
      }
      int importedCount = 0;
      for (var folder in importedComics.keys) {
        for (var comic in importedComics[folder]!) {
          var id = LocalManager().findValidId(ComicType.local);
          LocalManager().add(comic, id);
          importedCount++;
          if (folder != null) {
            LocalFavoritesManager().addComic(
              folder,
              FavoriteItem(
                id: id,
                name: comic.title,
                coverPath: comic.cover,
                author: comic.subtitle,
                type: comic.comicType,
                tags: comic.tags,
                favoriteTime: comic.createdAt,
              ),
            );
          }
        }
      }
      App.rootContext.showMessage(
        message: "Imported @a comics".tlParams({'a': importedCount}),
      );
    } catch (e, s) {
      App.rootContext.showMessage(message: "Failed to register comics".tl);
      Log.error("Import Comic", e.toString(), s);
      return false;
    }
    return true;
  }
}
