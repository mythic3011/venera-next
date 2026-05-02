import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_7zip/flutter_7zip.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/utils/local_import_storage.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/file_type.dart';
import 'package:venera/utils/import_sort.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';
import 'package:zip_flutter/zip_flutter.dart';

void _copyFilesWorker(List<Object?> args) {
  final sendPort = args[0] as SendPort;
  final tasks = (args[1] as List).cast<Map<String, String>>();
  try {
    final total = tasks.length;
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final src = File(task['src']!);
      final dst = File(task['dst']!);
      src.copySync(dst.path);
      if ((i + 1) % 20 == 0 || i == tasks.length - 1) {
        sendPort.send(<String, int>{'done': i + 1, 'total': total});
      }
    }
    sendPort.send(const <String, bool>{'doneAll': true});
  } catch (e) {
    sendPort.send(<String, String>{'error': e.toString()});
  }
}

class ComicMetaData {
  final String title;

  final String author;

  final List<String> tags;

  final List<ComicChapter>? chapters;

  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'tags': tags,
    'chapters': chapters?.map((e) => e.toJson()).toList(),
  };

  ComicMetaData.fromJson(Map<String, dynamic> json)
    : title = json['title'],
      author = json['author'],
      tags = List<String>.from(json['tags']),
      chapters = json['chapters'] == null
          ? null
          : List<ComicChapter>.from(
              json['chapters'].map((e) => ComicChapter.fromJson(e)),
            );

  ComicMetaData({
    required this.title,
    required this.author,
    required this.tags,
    this.chapters,
  });
}

class ComicChapter {
  final String title;

  final int start;

  final int end;

  Map<String, dynamic> toJson() => {'title': title, 'start': start, 'end': end};

  ComicChapter.fromJson(Map<String, dynamic> json)
    : title = json['title'],
      start = json['start'],
      end = json['end'];

  ComicChapter({required this.title, required this.start, required this.end});
}

/// Comic Book Archive. Currently supports CBZ, ZIP and 7Z formats.
abstract class CBZ {
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'};

  static void assertLegacyLookupAvailableForImport(
    String comicTitle, {
    LegacyLocalComicLookupResult Function(String title)? lookup,
  }) {
    final result = (lookup ?? legacyLookupLocalComicByName).call(comicTitle);
    if (result is LegacyLocalComicLookupUnavailable) {
      throw Exception(
        'Local comics database unavailable (fail closed): ${result.code}',
      );
    }
  }

  @visibleForTesting
  static Future<void> assertCanonicalStorageReadyForImport(
    String comicTitle, {
    LocalImportStoragePort? storage,
  }) {
    return (storage ?? const CanonicalLocalImportStorage())
        .assertStorageReadyForImport(comicTitle);
  }

  static Future<T> _runWithImportCacheCleanup<T>(
    Directory cache,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } finally {
      await cache.deleteIgnoreError(recursive: true);
    }
  }

  @visibleForTesting
  static Future<T> runWithImportCacheCleanupForTesting<T>(
    Directory cache,
    Future<T> Function() action,
  ) {
    return _runWithImportCacheCleanup(cache, action);
  }

  static Future<Directory> _flattenSingleWrapper(Directory root) async {
    var current = root;
    while (true) {
      final children = await current
          .list()
          .where((e) => !isHiddenOrMacMetadataPath(e.name))
          .toList();
      if (children.length == 1 && children.first is Directory) {
        current = children.first as Directory;
        continue;
      }
      return current;
    }
  }

  static Future<List<File>> _collectImageFiles(Directory directory) async {
    final files = <File>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      if (isHiddenOrMacMetadataPath(entity.path)) {
        continue;
      }
      if (_imageExtensions.contains(entity.extension.toLowerCase())) {
        files.add(entity);
      }
    }
    naturalSortFiles(files);
    return files;
  }

  static Future<Map<String, List<File>>?> _collectTopLevelDirectoryChapters(
    Directory root,
  ) async {
    final chapterDirs = <Directory>[];
    await for (final entity in root.list(followLinks: false)) {
      if (isHiddenOrMacMetadataPath(entity.path)) {
        continue;
      }
      if (entity is File &&
          _imageExtensions.contains(entity.extension.toLowerCase())) {
        return null;
      }
      if (entity is Directory) {
        chapterDirs.add(entity);
      }
    }
    if (chapterDirs.length < 2) {
      return null;
    }
    final result = <String, List<File>>{};
    for (final dir in chapterDirs) {
      final chapterImages = await _collectImageFiles(dir);
      if (chapterImages.isEmpty) {
        continue;
      }
      result[dir.name] = chapterImages;
    }
    if (result.length < 2) {
      return null;
    }
    return result;
  }

  static Future<FileType> checkType(File file) async {
    var header = <int>[];
    await for (var bytes in file.openRead()) {
      header.addAll(bytes);
      if (header.length >= 32) break;
    }
    return detectFileType(header);
  }

  static Future<void> extractArchive(File file, Directory out) async {
    var fileType = await checkType(file);
    if (fileType.mime == 'application/zip') {
      await ZipFile.openAndExtractAsync(file.path, out.path, 4);
    } else if (fileType.mime == "application/x-7z-compressed") {
      await SZArchive.extractIsolates(file.path, out.path, 4);
    } else {
      throw Exception('Unsupported archive type');
    }
  }

  static Future<void> copyFilesInBackground(
    List<Map<String, String>> tasks, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (tasks.isEmpty) {
      return;
    }
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_copyFilesWorker, [
      receive.sendPort,
      tasks,
    ]);
    try {
      await for (final event in receive) {
        if (event is Map) {
          if (event.containsKey('error')) {
            throw Exception(event['error'].toString());
          }
          if (event.containsKey('done')) {
            final done = event['done'] as int;
            final total = event['total'] as int;
            onProgress?.call(done, total);
            continue;
          }
          if (event['doneAll'] == true) {
            break;
          }
        }
      }
    } finally {
      receive.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }

  static Future<LocalComic> _importExtractedDirectory(
    Directory cache,
    Directory root, {
    required LocalImportStoragePort storage,
    required String fallbackTitle,
    void Function(String message, double? progress)? onProgress,
  }) async {
    var metaDataFile = File(FilePath.join(root.path, 'metadata.json'));
    ComicMetaData? metaData;
    if (metaDataFile.existsSync()) {
      try {
        metaData = ComicMetaData.fromJson(
          jsonDecode(metaDataFile.readAsStringSync()),
        );
      } catch (_) {}
    }
    metaData ??= ComicMetaData(
      title: fallbackTitle,
      author: "",
      tags: [],
    );
    await assertCanonicalStorageReadyForImport(
      metaData.title,
      storage: storage,
    );
    if (await storage.hasDuplicateTitle(metaData.title)) {
      throw Exception('Comic with name ${metaData.title} already exists');
    }
    var files = await _collectImageFiles(root);
    if (files.isEmpty) {
      throw Exception('No images found in the archive');
    }
    final coverFile = files.firstWhereOrNull(
      (element) => element.basenameWithoutExt.toLowerCase() == 'cover',
    );
    final pageFiles = [...files];
    File effectiveCoverFile;
    if (coverFile != null) {
      effectiveCoverFile = coverFile;
      if (pageFiles.length > 1) {
        pageFiles.remove(coverFile);
      }
    } else {
      effectiveCoverFile = pageFiles.first;
    }
    Map<String, String>? cpMap;
    final localRootPath = await storage.requireRootPath();
    var title = sanitizeFileName(metaData.title);
    var dest = Directory(FilePath.join(localRootPath, title));
    if (dest.existsSync()) {
      title = findValidDirectoryName(localRootPath, title);
      dest = Directory(FilePath.join(localRootPath, title));
    }
    dest.createSync(recursive: true);
    await effectiveCoverFile.copyFast(
      FilePath.join(dest.path, 'cover.${effectiveCoverFile.extension}'),
    );
    final directoryChapters = metaData.chapters == null
        ? await _collectTopLevelDirectoryChapters(root)
        : null;
    if (metaData.chapters == null && directoryChapters == null) {
      final tasks = <Map<String, String>>[];
      for (var i = 0; i < pageFiles.length; i++) {
        final src = pageFiles[i];
        tasks.add({
          'src': src.path,
          'dst': FilePath.join(dest.path, '${i + 1}.${src.extension}'),
        });
      }
      await copyFilesInBackground(
        tasks,
        onProgress: (done, total) {
          final progress = 0.3 + (done / total) * 0.65;
          onProgress?.call("Copying pages".tl, progress.clamp(0.0, 0.95));
        },
      );
    } else {
      final chapters = <String, List<File>>{};
      if (metaData.chapters != null) {
        for (var chapter in metaData.chapters!) {
          chapters[chapter.title] = pageFiles.sublist(
            chapter.start - 1,
            chapter.end,
          );
        }
      } else {
        chapters.addAll(directoryChapters!);
      }
      int i = 0;
      cpMap = <String, String>{};
      final tasks = <Map<String, String>>[];
      for (var chapter in chapters.entries) {
        cpMap[i.toString()] = chapter.key;
        var chapterDir = Directory(FilePath.join(dest.path, i.toString()));
        chapterDir.createSync(recursive: true);
        for (var pageIndex = 0; pageIndex < chapter.value.length; pageIndex++) {
          var src = chapter.value[pageIndex];
          tasks.add({
            'src': src.path,
            'dst': FilePath.join(
              chapterDir.path,
              '${pageIndex + 1}.${src.extension}',
            ),
          });
        }
        i++;
      }
      await copyFilesInBackground(
        tasks,
        onProgress: (done, total) {
          final progress = 0.3 + (done / total) * 0.65;
          onProgress?.call("Copying chapters".tl, progress.clamp(0.0, 0.95));
        },
      );
    }
    onProgress?.call("Finalizing import".tl, 1.0);
    return LocalComic(
      id: '0',
      title: metaData.title,
      subtitle: metaData.author,
      tags: metaData.tags,
      comicType: ComicType.local,
      directory: dest.name,
      chapters: ComicChapters.fromJsonOrNull(cpMap),
      downloadedChapters: cpMap?.keys.toList() ?? [],
      cover: 'cover.${effectiveCoverFile.extension}',
      createdAt: DateTime.now(),
    );
  }

  @visibleForTesting
  static Future<LocalComic> importExtractedDirectoryForTesting(
    Directory cache,
    Directory root, {
    LocalImportStoragePort? localImportStorage,
    String fallbackTitle = 'test-comic',
    void Function(String message, double? progress)? onProgress,
  }) {
    return _importExtractedDirectory(
      cache,
      root,
      storage: localImportStorage ?? const CanonicalLocalImportStorage(),
      fallbackTitle: fallbackTitle,
      onProgress: onProgress,
    );
  }

  static Future<LocalComic> import(
    File file, {
    void Function(String message, double? progress)? onProgress,
    LocalImportStoragePort? localImportStorage,
  }) async {
    final storage = localImportStorage ?? const CanonicalLocalImportStorage();
    onProgress?.call("Preparing import".tl, 0.02);
    onProgress?.call("Extracting archive".tl, 0.08);
    var cache = Directory(FilePath.join(App.cachePath, 'cbz_import'));
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    cache.createSync();
    return _runWithImportCacheCleanup(cache, () async {
      await extractArchive(file, cache);
      onProgress?.call("Scanning images".tl, 0.2);
      final root = await _flattenSingleWrapper(cache);
      return _importExtractedDirectory(
        cache,
        root,
        storage: storage,
        fallbackTitle: file.name.substring(0, file.name.lastIndexOf('.')),
        onProgress: onProgress,
      );
    });
  }

  static Future<File> export(LocalComic comic, String outFilePath) async {
    var cache = Directory(FilePath.join(App.cachePath, 'cbz_export'));
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    cache.createSync();
    List<ComicChapter>? chapters;
    if (comic.chapters == null) {
      var images = await legacyLoadLocalComicImages(
        comic.id,
        comic.comicType,
        1,
      );
      int i = 1;
      for (var image in images) {
        var src = File(image.replaceFirst('file://', ''));
        var width = images.length.toString().length;
        var dstName =
            '${i.toString().padLeft(width, '0')}.${image.split('.').last}';
        var dst = File(FilePath.join(cache.path, dstName));
        await src.copyMem(dst.path);
        i++;
      }
    } else {
      chapters = [];
      var allImages = <String>[];
      for (var c in comic.downloadedChapters) {
        var chapterName = comic.chapters![c];
        var images = await legacyLoadLocalComicImages(
          comic.id,
          comic.comicType,
          c,
        );
        allImages.addAll(images);
        var chapter = ComicChapter(
          title: chapterName!,
          start: chapters.length + 1,
          end: chapters.length + images.length,
        );
        chapters.add(chapter);
      }
      int i = 1;
      for (var image in allImages) {
        var src = File(image);
        var width = allImages.length.toString().length;
        var dstName =
            '${i.toString().padLeft(width, '0')}.${image.split('.').last}';
        var dst = File(FilePath.join(cache.path, dstName));
        await src.copyMem(dst.path);
        i++;
      }
    }
    var cover = comic.coverFile;
    await cover.copyMem(
      FilePath.join(cache.path, 'cover.${cover.path.split('.').last}'),
    );
    final metaData = ComicMetaData(
      title: comic.title,
      author: comic.subtitle,
      tags: comic.tags,
      chapters: chapters,
    );
    await File(
      FilePath.join(cache.path, 'metadata.json'),
    ).writeAsString(jsonEncode(metaData));
    await File(
      FilePath.join(cache.path, 'ComicInfo.xml'),
    ).writeAsString(_buildComicInfoXml(metaData));
    var cbz = File(outFilePath);
    if (cbz.existsSync()) cbz.deleteSync();
    await _compress(cache.path, cbz.path);
    cache.deleteSync(recursive: true);
    return cbz;
  }

  static String _buildComicInfoXml(ComicMetaData data) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln(
      '<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">',
    );

    buffer.writeln('  <Title>${_escapeXml(data.title)}</Title>');
    buffer.writeln('  <Series>${_escapeXml(data.title)}</Series>');

    if (data.author.isNotEmpty) {
      buffer.writeln('  <Writer>${_escapeXml(data.author)}</Writer>');
    }

    if (data.tags.isNotEmpty) {
      var tags = data.tags;
      if (tags.length > 5) {
        tags = tags.sublist(0, 5);
      }
      buffer.writeln('  <Genre>${_escapeXml(tags.join(', '))}</Genre>');
    }

    if (data.chapters != null && data.chapters!.isNotEmpty) {
      final chaptersInfo = data.chapters!
          .map(
            (chapter) =>
                '${_escapeXml(chapter.title)}: ${chapter.start}-${chapter.end}',
          )
          .join('; ');
      buffer.writeln('  <Notes>Chapters: $chaptersInfo</Notes>');
    }

    buffer.writeln('  <Manga>Unknown</Manga>');
    buffer.writeln('  <BlackAndWhite>Unknown</BlackAndWhite>');

    final now = DateTime.now();
    buffer.writeln('  <Year>${now.year}</Year>');

    buffer.writeln('</ComicInfo>');
    return buffer.toString();
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static _compress(String src, String dst) async {
    await ZipFile.compressFolderAsync(src, dst, 4);
  }
}
