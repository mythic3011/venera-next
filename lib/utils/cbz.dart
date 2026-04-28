import 'dart:convert';
import 'dart:isolate';
import 'package:flutter_7zip/flutter_7zip.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
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

  static Future<LocalComic> import(
    File file, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    onProgress?.call("Preparing import".tl, 0.02);
    onProgress?.call("Extracting archive".tl, 0.08);
    var cache = Directory(FilePath.join(App.cachePath, 'cbz_import'));
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    cache.createSync();
    await extractArchive(file, cache);
    onProgress?.call("Scanning images".tl, 0.2);
    cache = await _flattenSingleWrapper(cache);
    var metaDataFile = File(FilePath.join(cache.path, 'metadata.json'));
    ComicMetaData? metaData;
    if (metaDataFile.existsSync()) {
      try {
        metaData = ComicMetaData.fromJson(
          jsonDecode(metaDataFile.readAsStringSync()),
        );
      } catch (_) {}
    }
    metaData ??= ComicMetaData(
      title: file.name.substring(0, file.name.lastIndexOf('.')),
      author: "",
      tags: [],
    );
    var old = LocalManager().findByName(metaData.title);
    if (old != null) {
      throw Exception('Comic with name ${metaData.title} already exists');
    }
    var files = await _collectImageFiles(cache);
    if (files.isEmpty) {
      cache.deleteSync(recursive: true);
      throw Exception('No images found in the archive');
    }
    var coverFile = files.firstWhereOrNull(
      (element) => element.basenameWithoutExt.toLowerCase() == 'cover',
    );
    if (coverFile != null) {
      files.remove(coverFile);
    } else {
      coverFile = files.first;
    }
    Map<String, String>? cpMap;
    var dest = Directory(
      FilePath.join(LocalManager().path, sanitizeFileName(metaData.title)),
    );
    dest.createSync();
    await coverFile.copyFast(
      FilePath.join(dest.path, 'cover.${coverFile.extension}'),
    );
    final directoryChapters = metaData.chapters == null
        ? await _collectTopLevelDirectoryChapters(cache)
        : null;
    if (metaData.chapters == null && directoryChapters == null) {
      final tasks = <Map<String, String>>[];
      for (var i = 0; i < files.length; i++) {
        final src = files[i];
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
      dest.createSync();
      final chapters = <String, List<File>>{};
      if (metaData.chapters != null) {
        for (var chapter in metaData.chapters!) {
          chapters[chapter.title] = files.sublist(
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
        chapterDir.createSync();
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
    var comic = LocalComic(
      id: LocalManager().findValidId(ComicType.local),
      title: metaData.title,
      subtitle: metaData.author,
      tags: metaData.tags,
      comicType: ComicType.local,
      directory: dest.name,
      chapters: ComicChapters.fromJsonOrNull(cpMap),
      downloadedChapters: cpMap?.keys.toList() ?? [],
      cover: 'cover.${coverFile.extension}',
      createdAt: DateTime.now(),
    );
    onProgress?.call("Finalizing import".tl, 1.0);
    await cache.delete(recursive: true);
    return comic;
  }

  static Future<File> export(LocalComic comic, String outFilePath) async {
    var cache = Directory(FilePath.join(App.cachePath, 'cbz_export'));
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    cache.createSync();
    List<ComicChapter>? chapters;
    if (comic.chapters == null) {
      var images = await LocalManager().getImages(comic.id, comic.comicType, 1);
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
        var images = await LocalManager().getImages(
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
