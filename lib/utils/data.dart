import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/sources/identity/source_identity.dart';
import 'package:venera/network/cookie_jar.dart';
import 'package:venera/utils/ext.dart';
import 'package:zip_flutter/zip_flutter.dart';

import 'io.dart';

typedef _ArchiveExtractor = Future<void> Function(
  String archivePath,
  String outputDir,
);

_ArchiveExtractor _archiveExtractor = _defaultArchiveExtractor;

Future<void> _defaultArchiveExtractor(String archivePath, String outputDir) {
  return Isolate.run(() {
    ZipFile.openAndExtract(archivePath, outputDir);
  });
}

Future<void> _extractArchive(String archivePath, String outputDir) {
  return _archiveExtractor(archivePath, outputDir);
}

@visibleForTesting
void setArchiveExtractorForTest(
  Future<void> Function(String archivePath, String outputDir)? extractor,
) {
  _archiveExtractor = extractor ?? _defaultArchiveExtractor;
}

Future<File> exportAppData([bool sync = true]) async {
  var time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  var cacheFilePath = FilePath.join(App.cachePath, '$time.venera');
  var cacheFile = File(cacheFilePath);
  var dataPath = App.dataPath;
  if (await cacheFile.exists()) {
    await cacheFile.delete();
  }
  await Isolate.run(() {
    var zipFile = ZipFile.open(cacheFilePath);
    // Legacy DB export only. Do not use these files as runtime authority.
    var legacyHistoryDb = FilePath.join(dataPath, "history.db");
    var legacyFavoritesDb = FilePath.join(dataPath, "local_favorite.db");
    var appdata = FilePath.join(
      dataPath,
      sync ? "syncdata.json" : "appdata.json",
    );
    var cookies = FilePath.join(dataPath, "cookie.db");
    zipFile.addFile("history.db", legacyHistoryDb);
    zipFile.addFile("local_favorite.db", legacyFavoritesDb);
    zipFile.addFile("appdata.json", appdata);
    zipFile.addFile("cookie.db", cookies);
    for (var file in Directory(
      FilePath.join(dataPath, "comic_source"),
    ).listSync()) {
      if (file is File) {
        zipFile.addFile("comic_source/${file.name}", file.path);
      }
    }
    zipFile.close();
  });
  return cacheFile;
}

Future<void> importAppData(File file, [bool checkVersion = false]) async {
  var cacheDirPath = FilePath.join(App.cachePath, 'temp_data');
  var cacheDir = Directory(cacheDirPath);
  if (cacheDir.existsSync()) {
    cacheDir.deleteSync(recursive: true);
  }
  cacheDir.createSync();
  try {
    await _extractArchive(file.path, cacheDirPath);
    // Legacy DB restore only. Do not call from reader/home/history runtime paths.
    var legacyHistoryDb = cacheDir.joinFile("history.db");
    var legacyFavoritesDb = cacheDir.joinFile("local_favorite.db");
    var appdataFile = cacheDir.joinFile("appdata.json");
    var cookieFile = cacheDir.joinFile("cookie.db");
    if (checkVersion && appdataFile.existsSync()) {
      var data = jsonDecode(await appdataFile.readAsString());
      var version = data["settings"]["dataVersion"];
      if (version is int && version <= appdata.settings["dataVersion"]) {
        return;
      }
    }
    // Runtime authority boundary:
    // Do not restore legacy runtime DB files into App.dataPath.
    // Legacy DB imports must go through explicit migration/import entrypoints.
    if (await legacyHistoryDb.exists()) {
      AppDiagnostics.warn(
        'data.import',
        'import.skip_legacy_history_db_restore',
      );
    }
    if (await legacyFavoritesDb.exists()) {
      AppDiagnostics.warn(
        'data.import',
        'import.skip_legacy_favorites_db_restore',
      );
    }
    if (await appdataFile.exists()) {
      var content = await appdataFile.readAsString();
      var data = jsonDecode(content);
      appdata.syncData(data);
    }
    if (await cookieFile.exists()) {
      SingleInstanceCookieJar.instance?.dispose();
      File(FilePath.join(App.dataPath, "cookie.db")).deleteIfExistsSync();
      cookieFile.renameSync(FilePath.join(App.dataPath, "cookie.db"));
      SingleInstanceCookieJar.instance = SingleInstanceCookieJar(
        FilePath.join(App.dataPath, "cookie.db"),
      )..init();
    }
    var comicSourceDir = FilePath.join(cacheDirPath, "comic_source");
    if (Directory(comicSourceDir).existsSync()) {
      Directory(
        FilePath.join(App.dataPath, "comic_source"),
      ).deleteIfExistsSync(recursive: true);
      Directory(FilePath.join(App.dataPath, "comic_source")).createSync();
      for (var file in Directory(comicSourceDir).listSync()) {
        if (file is File) {
          var targetFile = FilePath.join(
            App.dataPath,
            "comic_source",
            file.name,
          );
          await file.copy(targetFile);
        }
      }
      await ComicSourceManager().reload();
    }
  } finally {
    cacheDir.deleteIgnoreError(recursive: true);
  }
}

Future<void> importPicaData(File file) async {
  var cacheDirPath = FilePath.join(App.cachePath, 'temp_data');
  var cacheDir = Directory(cacheDirPath);
  if (cacheDir.existsSync()) {
    cacheDir.deleteSync(recursive: true);
  }
  cacheDir.createSync();
  try {
    await _extractArchive(file.path, cacheDirPath);
    var legacyFavoritesDb = cacheDir.joinFile("local_favorite.db");
    if (legacyFavoritesDb.existsSync()) {
      var db = sqlite3.open(legacyFavoritesDb.path);
      try {
        var folderNames = db
            .select("SELECT name FROM sqlite_master WHERE type='table';")
            .map((e) => e["name"] as String)
            .toList();
        folderNames.removeWhere(
          (e) => e == "folder_order" || e == "folder_sync",
        );
        for (var folderSyncValue in db.select("SELECT * FROM folder_sync;")) {
          var folderName = folderSyncValue["folder_name"];
          String sourceKey = normalizeLegacyImportedSourceKey(
            folderSyncValue["key"],
          );
          // 有值就跳过
          if (LocalFavoritesManager().findLinked(folderName).$1 != null) {
            continue;
          }
          try {
            LocalFavoritesManager().linkFolderToNetwork(
              folderName,
              sourceKey,
              jsonDecode(folderSyncValue["sync_data"])["folderId"],
            );
          } catch (e, stack) {
            AppDiagnostics.error('data.import', e, stackTrace: stack);
          }
        }
        for (var folderName in folderNames) {
          if (!LocalFavoritesManager().existsFolder(folderName)) {
            LocalFavoritesManager().createFolder(folderName);
          }
          for (var comic in db.select("SELECT * FROM \"$folderName\";")) {
            LocalFavoritesManager().addComic(
              folderName,
              FavoriteItem(
                id: comic['target'],
                name: comic['name'],
                coverPath: comic['cover_path'],
                author: comic['author'],
                type: ComicType(
                  normalizeFavoriteJsonTypeValue(
                    typeValue: comic['type'],
                    coverPath: comic['cover_path'],
                  ),
                ),
                tags: comic['tags'].split(','),
              ),
            );
          }
        }
      } catch (e) {
        AppDiagnostics.error(
          'data.import',
          e,
          message: 'import.local_favorite_failed',
        );
      } finally {
        db.dispose();
      }
    }
    var legacyHistoryDb = cacheDir.joinFile("history.db");
    if (legacyHistoryDb.existsSync()) {
      var db = sqlite3.open(legacyHistoryDb.path);
      try {
        for (var comic in db.select("SELECT * FROM history;")) {
          await HistoryManager().addHistory(
            History.fromMap({
              "type": normalizeLegacyHistoryTypeValue(comic['type']),
              "id": comic['target'],
              "max_page": comic["max_page"],
              "ep": comic["ep"],
              "page": comic["page"],
              "time": comic["time"],
              "title": comic["title"],
              "subtitle": comic["subtitle"],
              "cover": comic["cover"],
              "readEpisode": [comic["ep"]],
            }),
          );
        }
        List<ImageFavoritesComic> imageFavoritesComicList =
            ImageFavoriteManager().comics;
        for (var comic in db.select("SELECT * FROM image_favorites;")) {
          String sourceKey = normalizeLegacyImportedSourceKey(
            comic["id"].split("-")[0],
          );
          if (ComicSource.find(sourceKey) == null) {
            continue;
          }
          String id = comic["id"].split("-")[1];
          int page = comic["page"];
          // 章节和page是从1开始的, pica 可能有从 0 开始的, 得转一下
          int ep = comic["ep"] == 0 ? 1 : comic["ep"];
          String title = comic["title"];
          String epName = "";
          ImageFavoritesComic? tempComic = imageFavoritesComicList
              .firstWhereOrNull((e) => e.id == id && e.sourceKey == sourceKey);
          ImageFavorite curImageFavorite = ImageFavorite(
            page,
            "",
            null,
            "",
            id,
            ep,
            sourceKey,
            epName,
          );
          if (tempComic == null) {
            tempComic = ImageFavoritesComic(
              id,
              [],
              title,
              sourceKey,
              [],
              [],
              DateTime.now(),
              "",
              {},
              "",
              1,
            );
            tempComic.imageFavoritesEp = [
              ImageFavoritesEp("", ep, [curImageFavorite], epName, 1),
            ];
            imageFavoritesComicList.add(tempComic);
          } else {
            ImageFavoritesEp? tempEp = tempComic.imageFavoritesEp
                .firstWhereOrNull((e) => e.ep == ep);
            if (tempEp == null) {
              tempComic.imageFavoritesEp.add(
                ImageFavoritesEp("", ep, [curImageFavorite], epName, 1),
              );
            } else {
              // 如果已经有这个page了, 就不添加了
              if (tempEp.imageFavorites.firstWhereOrNull(
                    (e) => e.page == page,
                  ) ==
                  null) {
                tempEp.imageFavorites.add(curImageFavorite);
              }
            }
          }
        }
        for (var temp in imageFavoritesComicList) {
          ImageFavoriteManager().addOrUpdateOrDelete(
            temp,
            temp == imageFavoritesComicList.last,
          );
        }
      } catch (e, stack) {
        AppDiagnostics.error(
          'data.import',
          e,
          stackTrace: stack,
          message: 'import.history_failed',
        );
      } finally {
        db.dispose();
      }
    }
  } finally {
    cacheDir.deleteIgnoreError(recursive: true);
  }
}
