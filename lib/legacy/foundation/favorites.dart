import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/db/favorites_store.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/image_provider/local_favorite_image.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/foundation/sources/identity/source_identity.dart';
import 'package:venera/pages/follow_updates_page.dart';
import 'package:venera/utils/tags_translation.dart';

import 'package:venera/foundation/app/app.dart';
import 'comic_type.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';

typedef DeleteLocalComicFromFavoritesForTest =
    void Function(String id, ComicType type);

String quoteSqlIdent(String ident) {
  if (ident.contains('\u0000')) {
    throw ArgumentError('Invalid SQLite identifier');
  }
  return '"${ident.replaceAll('"', '""')}"';
}

String _getTimeString(DateTime time) {
  return time.toIso8601String().replaceFirst("T", " ").substring(0, 19);
}

class FavoriteItem implements Comic {
  String name;
  String author;
  ComicType type;
  @override
  List<String> tags;
  @override
  String id;
  String coverPath;
  late String time;

  FavoriteItem({
    required this.id,
    required this.name,
    required this.coverPath,
    required this.author,
    required this.type,
    required this.tags,
    DateTime? favoriteTime,
  }) {
    var t = favoriteTime ?? DateTime.now();
    time = _getTimeString(t);
  }

  FavoriteItem.fromRow(Row row)
    : this._fromTrustedRow(
        tryFromRow(row) ?? (throw const FormatException('Invalid favorite row')),
      );

  FavoriteItem._fromTrustedRow(FavoriteItem item)
    : name = item.name,
      author = item.author,
      type = item.type,
      tags = List<String>.from(item.tags),
      id = item.id,
      coverPath = item.coverPath,
      time = item.time;

  FavoriteItem.fromRecord(FavoriteComicRecord row)
    : name = row.name,
      author = row.author,
      type = ComicType(row.type),
      tags = row.tags.split(","),
      id = row.id,
      coverPath = row.coverPath,
      time = row.time {
    tags.remove("");
  }

  @override
  bool operator ==(Object other) {
    return other is FavoriteItem && other.id == id && other.type == type;
  }

  @override
  int get hashCode => id.hashCode ^ type.hashCode;

  @override
  String toString() {
    var s = "FavoriteItem: $name $author $coverPath $hashCode $tags";
    if (s.length > 100) {
      return s.substring(0, 100);
    }
    return s;
  }

  @override
  String get cover => coverPath;

  @override
  String get description {
    final time = this.time.length >= 10 ? this.time.substring(0, 10) : 'Unknown';
    return appdata.settings['comicDisplayMode'] == 'detailed'
        ? "$time | ${type == ComicType.local ? 'local' : type.comicSource?.name ?? "Unknown"}"
        : "${type.comicSource?.name ?? "Unknown"} | $time";
  }

  @override
  String? get favoriteId => null;

  @override
  String? get language => null;

  @override
  int? get maxPage => null;

  @override
  String get sourceKey =>
      type == ComicType.local ? localSourceKey : type.sourceKey;

  @override
  double? get stars => null;

  @override
  String? get subtitle => author;

  @override
  String get title => name;

  @override
  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "author": author,
      "type": type.value,
      "tags": tags,
      "id": id,
      "coverPath": coverPath,
    };
  }

  static FavoriteItem? tryFromRow(Row row, {String? folder}) {
    try {
      final id = row['id']?.toString();
      final name = row['name']?.toString();
      final rawType = row['type'];
      if (id == null || id.isEmpty || name == null || rawType is! int) {
        AppDiagnostics.warn(
          'favorites.store',
          'Dropped malformed favorite row',
          data: {
            'folder': folder,
            'id': id,
            'name': name,
            'type': rawType?.toString(),
          },
        );
        return null;
      }
      final rawTags = row['tags']?.toString() ?? '';
      return FavoriteItem(
        id: id,
        name: name,
        author: row['author']?.toString() ?? '',
        coverPath: row['cover_path']?.toString() ?? '',
        type: ComicType(rawType),
        tags: rawTags.split(',').where((e) => e.isNotEmpty).toList(),
        favoriteTime: DateTime.tryParse(row['time']?.toString() ?? ''),
      );
    } catch (e, stackTrace) {
      AppDiagnostics.warn(
        'favorites.store',
        'Failed to parse favorite row',
        data: {
          'folder': folder,
          'error': '$e',
          'stackTrace': '$stackTrace',
        },
      );
      return null;
    }
  }

  static FavoriteItem fromJson(Map<String, dynamic> json) {
    return tryFromJson(json) ??
        (throw const FormatException('Invalid favorite json'));
  }

  static FavoriteItem? tryFromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    final typeValue = rawType is int
        ? rawType
        : int.tryParse(rawType?.toString() ?? '');
    final id = (json['id'] ?? json['target'])?.toString();
    if (typeValue == null || id == null || id.isEmpty) {
      return null;
    }
    final coverPath = json['coverPath']?.toString() ?? '';
    final normalizedType = normalizeFavoriteJsonTypeValue(
      typeValue: typeValue,
      coverPath: coverPath,
    );
    final rawTags = json['tags'];
    final tags = rawTags is List
        ? rawTags.whereType<String>().toList()
        : const <String>[];
    return FavoriteItem(
      id: id,
      name: json['name']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      coverPath: coverPath,
      type: ComicType(normalizedType),
      tags: tags,
    );
  }
}

class FavoriteItemWithFolderInfo extends FavoriteItem {
  String folder;

  FavoriteItemWithFolderInfo(FavoriteItem item, this.folder)
    : super(
        id: item.id,
        name: item.name,
        coverPath: item.coverPath,
        author: item.author,
        type: item.type,
        tags: item.tags,
      );
}

class FavoriteItemWithUpdateInfo extends FavoriteItem {
  String? updateTime;

  DateTime? lastCheckTime;

  bool hasNewUpdate;

  FavoriteItemWithUpdateInfo(
    FavoriteItem item,
    this.updateTime,
    this.hasNewUpdate,
    int? lastCheckTime,
  ) : lastCheckTime = lastCheckTime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastCheckTime),
      super(
        id: item.id,
        name: item.name,
        coverPath: item.coverPath,
        author: item.author,
        type: item.type,
        tags: item.tags,
      );

  @override
  String get description {
    var updateTime = this.updateTime ?? "Unknown";
    var sourceName = type.comicSource?.name ?? "Unknown";
    return "$updateTime | $sourceName";
  }

  @override
  operator ==(Object other) {
    return other is FavoriteItemWithUpdateInfo &&
        other.updateTime == updateTime &&
        other.hasNewUpdate == hasNewUpdate &&
        super == other;
  }

  @override
  int get hashCode =>
      super.hashCode ^ updateTime.hashCode ^ hasNewUpdate.hashCode;
}

class LocalFavoritesManager with ChangeNotifier {
  factory LocalFavoritesManager() =>
      cache ?? (cache = LocalFavoritesManager._create());

  LocalFavoritesManager._create();

  static LocalFavoritesManager? cache;
  static DeleteLocalComicFromFavoritesForTest? deleteLocalComicOverrideForTest;

  late Database _db;
  late FavoritesStore _store;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  @visibleForTesting
  void markInitializedForTest(bool value) {
    _isInitialized = value;
  }

  late Map<String, int> counts;

  var _hashedIds = <int, int>{};

  int get totalComics {
    return _hashedIds.length;
  }

  int folderComics(String folder) {
    return counts[folder] ?? 0;
  }

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    counts = {};
    final canonicalDbPath = canonicalDomainDatabasePath(App.dataPath);
    Directory(File(canonicalDbPath).parent.path).createSync(recursive: true);
    _db = sqlite3.open(canonicalDbPath);
    _store = FavoritesStore(canonicalDbPath);
    AppDiagnostics.info(
      'storage.route',
      'Favorites runtime routed to canonical DB file',
      data: {
        'domain': 'favorites',
        'route': 'canonical',
        'legacyDbFile': 'local_favorite.db',
        'canonicalDbFile': canonicalDomainDatabaseFileName,
      },
    );
    _db.execute("""
      create table if not exists folder_order (
        folder_name text primary key,
        order_value int
      );
    """);
    _db.execute("""
      create table if not exists folder_sync (
        folder_name text primary key,
        source_key text,
        source_folder text
      );
    """);
    var folderNames = _getFolderNamesWithDB();
    await appdata.ensureInit();
    // Make sure the follow updates folder is ready
    var followUpdateFolder = appdata.settings['followUpdatesFolder'];
    if (followUpdateFolder is String &&
        folderNames.contains(followUpdateFolder)) {
      prepareTableForFollowUpdates(followUpdateFolder, false);
    } else {
      appdata.settings['followUpdatesFolder'] = null;
    }
    initCounts();
    _isInitialized = true;
  }

  void initCounts() {
    for (var folder in folderNames) {
      counts[folder] = count(folder);
    }
    _store.loadHashedIds(folderNames).then((value) {
      _hashedIds = value;
      notifyListeners();
    });
  }

  void refreshHashedIds() {
    _store.loadHashedIds(folderNames).then((value) {
      _hashedIds = value;
      notifyListeners();
    });
  }

  void reduceHashedId(String id, int type) {
    var hash = id.hashCode ^ type;
    if (_hashedIds.containsKey(hash)) {
      if (_hashedIds[hash]! > 1) {
        _hashedIds[hash] = _hashedIds[hash]! - 1;
      } else {
        _hashedIds.remove(hash);
      }
    }
  }

  String _canonicalComicIdForFavorite({
    required String comicId,
    required ComicType type,
  }) {
    if (type == ComicType.local) {
      return comicId;
    }
    return canonicalRemoteComicId(sourceKey: type.sourceKey, comicId: comicId);
  }

  void _runCanonicalSync(
    Future<void> Function(UnifiedComicsStore store) action,
  ) {
    final store = App.unifiedComicsStoreOrNull;
    if (store == null) {
      return;
    }
    Future.microtask(() => action(store));
  }

  void _syncCanonicalFavoriteAdd(FavoriteItem comic) {
    _runCanonicalSync((store) async {
      await store.upsertFavorite(
        FavoriteRecord(
          comicId: _canonicalComicIdForFavorite(
            comicId: comic.id,
            type: comic.type,
          ),
          sourceKey: comic.sourceKey,
          createdAt: null,
        ),
      );
    });
  }

  void _syncCanonicalFolderUpsert({
    required String folderName,
    int orderValue = 0,
    String? sourceKey,
    String? sourceFolder,
  }) {
    _runCanonicalSync((store) async {
      await store.upsertFavoriteFolder(
        FavoriteFolderRecord(
          folderName: folderName,
          orderValue: orderValue,
          sourceKey: sourceKey,
          sourceFolder: sourceFolder,
        ),
      );
    });
  }

  void _syncCanonicalFolderDelete(String folderName) {
    _runCanonicalSync((store) async {
      await store.deleteFavoriteFolder(folderName);
    });
  }

  void _syncCanonicalFolderRename({
    required String before,
    required String after,
  }) {
    _runCanonicalSync((store) async {
      await store.renameFavoriteFolder(before: before, after: after);
    });
  }

  void _syncCanonicalFolderOrder(List<String> folders) {
    _runCanonicalSync((store) async {
      await store.replaceFavoriteFolderOrder(folders);
    });
  }

  void _syncCanonicalFolderItemUpsert({
    required String folderName,
    required String comicId,
    required ComicType type,
    required int displayOrder,
  }) {
    _runCanonicalSync((store) async {
      await store.upsertFavoriteFolderItem(
        FavoriteFolderItemRecord(
          folderName: folderName,
          comicId: _canonicalComicIdForFavorite(comicId: comicId, type: type),
          displayOrder: displayOrder,
        ),
      );
    });
  }

  void _syncCanonicalFolderItemDelete({
    required String folderName,
    required String comicId,
    required ComicType type,
  }) {
    _runCanonicalSync((store) async {
      await store.deleteFavoriteFolderItem(
        folderName: folderName,
        comicId: _canonicalComicIdForFavorite(comicId: comicId, type: type),
      );
    });
  }

  void _syncCanonicalFavoriteDeleteIfOrphan({
    required String comicId,
    required ComicType type,
  }) {
    if (_existsInAnyFolder(comicId, type)) {
      return;
    }
    _runCanonicalSync((store) async {
      await store.deleteFavorite(
        _canonicalComicIdForFavorite(comicId: comicId, type: type),
      );
    });
  }

  List<String> find(String id, ComicType type) {
    var res = <String>[];
    for (var folder in folderNames) {
      final quotedFolder = quoteSqlIdent(folder);
      var rows = _db.select(
        """
        select * from $quotedFolder
        where id == ? and type == ?;
      """,
        [id, type.value],
      );
      if (rows.isNotEmpty) {
        res.add(folder);
      }
    }
    return res;
  }

  Future<List<String>> findWithModel(FavoriteItem item) async {
    var res = <String>[];
    for (var folder in folderNames) {
      final quotedFolder = quoteSqlIdent(folder);
      var rows = _db.select(
        """
        select * from $quotedFolder
        where id == ? and type == ?;
      """,
        [item.id, item.type.value],
      );
      if (rows.isNotEmpty) {
        res.add(folder);
      }
    }
    return res;
  }

  List<String> _getTablesWithDB() {
    final tables = _db
        .select("SELECT name FROM sqlite_master WHERE type='table';")
        .map((element) => element["name"] as String)
        .toList();
    return tables;
  }

  Set<String> _tableColumnNames(String tableName) {
    final quotedTable = quoteSqlIdent(tableName);
    return _db
        .select('pragma table_info($quotedTable);')
        .map((row) => row['name'] as String)
        .toSet();
  }

  bool _isReservedFavoritesTable(String tableName) {
    return tableName == 'folder_sync' ||
        tableName == 'folder_order' ||
        tableName.startsWith('sqlite_');
  }

  List<String> _getFolderNamesWithDB() {
    final folders = <String>[];
    for (final table in _getTablesWithDB()) {
      if (_looksLikeLegacyFavoriteFolderTable(table)) {
        _ensureFavoriteFolderSchema(table);
        folders.add(table);
      }
    }
    var folderToOrder = <String, int>{};
    for (var folder in folders) {
      var res = _db.select(
        """
        select * from folder_order
        where folder_name == ?;
      """,
        [folder],
      );
      if (res.isNotEmpty) {
        folderToOrder[folder] = res.first["order_value"];
      } else {
        folderToOrder[folder] = 0;
      }
    }
    folders.sort((a, b) {
      return folderToOrder[a]! - folderToOrder[b]!;
    });
    return folders;
  }

  bool _looksLikeLegacyFavoriteFolderTable(String tableName) {
    if (_isReservedFavoritesTable(tableName)) {
      return false;
    }
    final columns = _tableColumnNames(tableName);
    const requiredColumns = {
      'id',
      'name',
      'author',
      'type',
      'tags',
      'cover_path',
      'time',
    };
    return columns.containsAll(requiredColumns);
  }

  void _ensureFavoriteFolderSchema(String folder) {
    final quotedFolder = quoteSqlIdent(folder);
    final columns = _tableColumnNames(folder);
    if (!columns.contains('display_order')) {
      _db.execute(
        '''
        alter table $quotedFolder
        add column display_order int;
      ''',
      );
      _db.execute(
        '''
        update $quotedFolder
        set display_order = rowid
        where display_order is null;
      ''',
      );
    }
    if (!columns.contains('translated_tags')) {
      _db.execute(
        '''
        alter table $quotedFolder
        add column translated_tags TEXT;
      ''',
      );
      final rows = _db.select(
        '''
        select id, type, tags from $quotedFolder;
      ''',
      );
      for (final row in rows) {
        final translatedTags = _translateTags(
          (row['tags']?.toString() ?? '')
              .split(',')
              .where((e) => e.isNotEmpty)
              .toList(),
        );
        _db.execute(
          '''
          update $quotedFolder
          set translated_tags = ?
          where id == ? and type == ?;
        ''',
          [translatedTags, row['id'], row['type']],
        );
      }
    }
  }

  void updateOrder(List<String> folders) {
    for (int i = 0; i < folders.length; i++) {
      _db.execute(
        """
        insert or replace into folder_order (folder_name, order_value)
        values (?, ?);
      """,
        [folders[i], i],
      );
    }
    _syncCanonicalFolderOrder(folders);
    notifyListeners();
  }

  int count(String folderName) {
    final quotedFolder = quoteSqlIdent(folderName);
    return _db.select("""
      select count(*) as c
      from $quotedFolder
    """).first["c"];
  }

  List<String> get folderNames =>
      _isInitialized ? _getFolderNamesWithDB() : const [];

  int maxValue(String folder) {
    final quotedFolder = quoteSqlIdent(folder);
    return _db.select("""
        SELECT MAX(display_order) AS max_value
        FROM $quotedFolder;
      """).firstOrNull?["max_value"] ??
        0;
  }

  int minValue(String folder) {
    final quotedFolder = quoteSqlIdent(folder);
    return _db.select("""
        SELECT MIN(display_order) AS min_value
        FROM $quotedFolder;
      """).firstOrNull?["min_value"] ??
        0;
  }

  List<FavoriteItem> getFolderComics(String folder) {
    final quotedFolder = quoteSqlIdent(folder);
    var rows = _db.select("""
        select * from $quotedFolder
        ORDER BY display_order;
      """);
    return rows
        .map((row) => FavoriteItem.tryFromRow(row, folder: folder))
        .whereType<FavoriteItem>()
        .toList();
  }

  /// Start a new isolate to get the comics in the folder
  Future<List<FavoriteItem>> getFolderComicsAsync(String folder) {
    return _store
        .loadFolderComics(folder)
        .then((rows) => rows.map(FavoriteItem.fromRecord).toList());
  }

  List<FavoriteItem> getAllComics() {
    var res = <FavoriteItem>{};
    for (final folder in folderNames) {
      final quotedFolder = quoteSqlIdent(folder);
      var comics = _db.select("""
        select * from $quotedFolder;
      """);
      res.addAll(
        comics
            .map((row) => FavoriteItem.tryFromRow(row, folder: folder))
            .whereType<FavoriteItem>(),
      );
    }
    return res.toList();
  }

  /// Start a new isolate to get all the comics
  Future<List<FavoriteItem>> getAllComicsAsync() async {
    final res = <FavoriteItem>{};
    for (final folder in folderNames) {
      final comics = await _store.loadFolderComics(folder);
      res.addAll(comics.map(FavoriteItem.fromRecord));
    }
    return res.toList();
  }

  void addTagTo(String folder, String id, String tag) {
    final quotedFolder = quoteSqlIdent(folder);
    _db.execute(
      """
      update $quotedFolder
      set tags = '$tag,' || tags
      where id == ?
    """,
      [id],
    );
    notifyListeners();
  }

  List<FavoriteItemWithFolderInfo> allComics() {
    var res = <FavoriteItemWithFolderInfo>[];
    for (final folder in folderNames) {
      final quotedFolder = quoteSqlIdent(folder);
      var comics = _db.select("""
        select * from $quotedFolder;
      """);
      for (final row in comics) {
        final parsed = FavoriteItem.tryFromRow(row, folder: folder);
        if (parsed != null) {
          res.add(FavoriteItemWithFolderInfo(parsed, folder));
        }
      }
    }
    return res;
  }

  bool existsFolder(String name) {
    return folderNames.contains(name);
  }

  /// create a folder
  String createFolder(String name, [bool renameWhenInvalidName = false]) {
    if (name.isEmpty) {
      if (renameWhenInvalidName) {
        int i = 0;
        while (existsFolder(i.toString())) {
          i++;
        }
        name = i.toString();
      } else {
        throw "name is empty!";
      }
    }
    if (existsFolder(name)) {
      if (renameWhenInvalidName) {
        var prevName = name;
        int i = 0;
        while (existsFolder(i.toString())) {
          i++;
        }
        name = prevName + i.toString();
      } else {
        throw Exception("Folder is existing");
      }
    }
    _db.execute("""
      create table "$name"(
        id text,
        name TEXT,
        author TEXT,
        type int,
        tags TEXT,
        cover_path TEXT,
        time TEXT,
        display_order int,
        translated_tags TEXT,
        primary key (id, type)
      );
    """);
    notifyListeners();
    counts[name] = 0;
    _syncCanonicalFolderUpsert(folderName: name);
    return name;
  }

  void linkFolderToNetwork(String folder, String source, String networkFolder) {
    _db.execute(
      """
      insert or replace into folder_sync (folder_name, source_key, source_folder)
      values (?, ?, ?);
    """,
      [folder, source, networkFolder],
    );
    _syncCanonicalFolderUpsert(
      folderName: folder,
      orderValue: folderNames
          .indexOf(folder)
          .clamp(0, folderNames.length)
          .toInt(),
      sourceKey: source,
      sourceFolder: networkFolder,
    );
  }

  bool isLinkedToNetworkFolder(
    String folder,
    String source,
    String networkFolder,
  ) {
    var res = _db.select(
      """
      select * from folder_sync
      where folder_name == ? and source_key == ? and source_folder == ?;
    """,
      [folder, source, networkFolder],
    );
    return res.isNotEmpty;
  }

  (String?, String?) findLinked(String folder) {
    var res = _db.select(
      """
      select * from folder_sync
      where folder_name == ?;
    """,
      [folder],
    );
    if (res.isEmpty) {
      return (null, null);
    }
    return (res.first["source_key"], res.first["source_folder"]);
  }

  bool comicExists(String folder, String id, ComicType type) {
    final quotedFolder = quoteSqlIdent(folder);
    var res = _db.select(
      """
      select * from $quotedFolder
      where id == ? and type == ?;
    """,
      [id, type.value],
    );
    return res.isNotEmpty;
  }

  bool _existsInAnyFolder(String id, ComicType type) {
    for (final folder in folderNames) {
      if (comicExists(folder, id, type)) {
        return true;
      }
    }
    return false;
  }

  FavoriteItem getComic(String folder, String id, ComicType type) {
    var res = _db.select(
      """
      select * from "$folder"
      where id == ? and type == ?;
    """,
      [id, type.value],
    );
    if (res.isEmpty) {
      throw Exception("Comic not found");
    }
    return FavoriteItem.fromRow(res.first);
  }

  String _translateTags(List<String> tags) {
    var res = <String>[];
    for (var tag in tags) {
      var translated = tag.translateTagsToCN;
      if (translated != tag) {
        res.add(translated);
      }
    }
    return res.join(",");
  }

  /// add comic to a folder.
  /// return true if success, false if already exists
  bool addComic(
    String folder,
    FavoriteItem comic, [
    int? order,
    String? updateTime,
  ]) {
    if (!existsFolder(folder)) {
      throw Exception("Folder does not exists");
    }
    var res = _db.select(
      """
      select * from "$folder"
      where id == ? and type == ?;
    """,
      [comic.id, comic.type.value],
    );
    if (res.isNotEmpty) {
      return false;
    }
    var translatedTags = _translateTags(comic.tags);
    final record = FavoriteComicRecord(
      id: comic.id,
      name: comic.name,
      author: comic.author,
      type: comic.type.value,
      tags: comic.tags.join(","),
      coverPath: comic.coverPath,
      time: comic.time,
    );
    final displayOrder =
        order ??
        (appdata.settings['newFavoriteAddTo'] == "end"
            ? _store.maxDisplayOrder(folder) + 1
            : _store.minDisplayOrder(folder) - 1);
    _store.insertComic(
      folder,
      record,
      translatedTags,
      displayOrder,
      updateTime: updateTime,
    );
    if (counts[folder] == null) {
      counts[folder] = count(folder);
    } else {
      counts[folder] = counts[folder]! + 1;
    }
    var hash = comic.id.hashCode ^ comic.type.value;
    _hashedIds[hash] = (_hashedIds[hash] ?? 0) + 1;
    _syncCanonicalFavoriteAdd(comic);
    _syncCanonicalFolderItemUpsert(
      folderName: folder,
      comicId: comic.id,
      type: comic.type,
      displayOrder: displayOrder,
    );
    notifyListeners();
    return true;
  }

  void moveFavorite(
    String sourceFolder,
    String targetFolder,
    String id,
    ComicType type,
  ) {
    if (!existsFolder(sourceFolder)) {
      throw Exception("Source folder does not exist");
    }
    if (!existsFolder(targetFolder)) {
      throw Exception("Target folder does not exist");
    }

    if (_store.hasComic(targetFolder, id, type.value)) {
      return;
    }

    _store.moveFavorite(
      sourceFolder,
      targetFolder,
      id,
      type.value,
      _store.minDisplayOrder(targetFolder) - 1,
    );

    _syncCanonicalFolderItemDelete(
      folderName: sourceFolder,
      comicId: id,
      type: type,
    );
    _syncCanonicalFolderItemUpsert(
      folderName: targetFolder,
      comicId: id,
      type: type,
      displayOrder: _store.minDisplayOrder(targetFolder),
    );

    notifyListeners();
  }

  void batchMoveFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    if (!existsFolder(sourceFolder)) {
      throw Exception("Source folder does not exist");
    }
    if (!existsFolder(targetFolder)) {
      throw Exception("Target folder does not exist");
    }

    try {
      _store.batchMoveFavorites(
        sourceFolder,
        targetFolder,
        items
            .map(
              (item) => FavoriteComicRecord(
                id: item.id,
                name: item.name,
                author: item.author,
                type: item.type.value,
                tags: item.tags.join(","),
                coverPath: item.coverPath,
                time: item.time,
              ),
            )
            .toList(),
        _store.maxDisplayOrder(targetFolder) + 1,
      );
      final baseOrder = _store.maxDisplayOrder(targetFolder);
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        _syncCanonicalFolderItemDelete(
          folderName: sourceFolder,
          comicId: item.id,
          type: item.type,
        );
        _syncCanonicalFolderItemUpsert(
          folderName: targetFolder,
          comicId: item.id,
          type: item.type,
          displayOrder: baseOrder + i + 1,
        );
      }
      notifyListeners();
    } catch (e) {
      AppDiagnostics.error('favorites.batch', e, message: 'batch_move_failed');
      return;
    }

    // Update counts
    counts[targetFolder] = count(targetFolder);
    counts[sourceFolder] = count(sourceFolder);
    refreshHashedIds();

    notifyListeners();
  }

  void batchCopyFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    if (!existsFolder(sourceFolder)) {
      throw Exception("Source folder does not exist");
    }
    if (!existsFolder(targetFolder)) {
      throw Exception("Target folder does not exist");
    }

    try {
      _store.batchCopyFavorites(
        sourceFolder,
        targetFolder,
        items
            .map(
              (item) => FavoriteComicRecord(
                id: item.id,
                name: item.name,
                author: item.author,
                type: item.type.value,
                tags: item.tags.join(","),
                coverPath: item.coverPath,
                time: item.time,
              ),
            )
            .toList(),
        _store.maxDisplayOrder(targetFolder) + 1,
      );
      final baseOrder = _store.maxDisplayOrder(targetFolder);
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        _syncCanonicalFolderItemUpsert(
          folderName: targetFolder,
          comicId: item.id,
          type: item.type,
          displayOrder: baseOrder + i + 1,
        );
      }
      notifyListeners();
    } catch (e) {
      AppDiagnostics.error('favorites.batch', e, message: 'batch_copy_failed');
      return;
    }

    // Update counts
    counts[targetFolder] = count(targetFolder);
    refreshHashedIds();

    notifyListeners();
  }

  /// delete a folder
  void deleteFolder(String name) {
    _db.execute("""
      drop table "$name";
    """);
    _db.execute(
      """
      delete from folder_order
      where folder_name == ?;
    """,
      [name],
    );
    counts.remove(name);
    refreshHashedIds();
    _syncCanonicalFolderDelete(name);
    notifyListeners();
  }

  void deleteComicWithId(String folder, String id, ComicType type) {
    LocalFavoriteImageProvider.delete(id, type.value);
    _store.deleteComic(folder, id, type.value);
    if (counts[folder] != null) {
      counts[folder] = counts[folder]! - 1;
    } else {
      counts[folder] = count(folder);
    }
    reduceHashedId(id, type.value);
    _syncCanonicalFolderItemDelete(folderName: folder, comicId: id, type: type);
    _syncCanonicalFavoriteDeleteIfOrphan(comicId: id, type: type);
    notifyListeners();
  }

  void deleteLocalComicFromAllFoldersIfInitialized(String id, ComicType type) {
    if (!_isInitialized) {
      return;
    }
    final override = deleteLocalComicOverrideForTest;
    if (override != null) {
      override(id, type);
      return;
    }
    final folders = find(id, type);
    for (final folder in folders) {
      deleteComicWithId(folder, id, type);
    }
  }

  void batchDeleteComics(String folder, List<FavoriteItem> comics) {
    try {
      for (var comic in comics) {
        LocalFavoriteImageProvider.delete(comic.id, comic.type.value);
      }
      _store.batchDeleteComics(
        folder,
        comics
            .map(
              (comic) => FavoriteComicRecord(
                id: comic.id,
                name: comic.name,
                author: comic.author,
                type: comic.type.value,
                tags: comic.tags.join(","),
                coverPath: comic.coverPath,
                time: comic.time,
              ),
            )
            .toList(),
      );
      if (counts[folder] != null) {
        counts[folder] = counts[folder]! - comics.length;
      } else {
        counts[folder] = count(folder);
      }
    } catch (e) {
      AppDiagnostics.error('favorites.batch', e, message: 'batch_delete_failed');
      return;
    }
    for (var comic in comics) {
      reduceHashedId(comic.id, comic.type.value);
      _syncCanonicalFolderItemDelete(
        folderName: folder,
        comicId: comic.id,
        type: comic.type,
      );
      _syncCanonicalFavoriteDeleteIfOrphan(comicId: comic.id, type: comic.type);
    }
    notifyListeners();
  }

  void batchDeleteComicsInAllFolders(List<ComicID> comics) {
    _db.execute("BEGIN TRANSACTION");
    var folderNames = _getFolderNamesWithDB();
    try {
      for (var comic in comics) {
        LocalFavoriteImageProvider.delete(comic.id, comic.type.value);
        for (var folder in folderNames) {
          _db.execute(
            """
            delete from "$folder"
            where id == ? and type == ?;
          """,
            [comic.id, comic.type.value],
          );
        }
      }
    } catch (e) {
      AppDiagnostics.error('favorites.batch', e, message: 'batch_delete_all_folders_failed');
      _db.execute("ROLLBACK");
      return;
    }
    initCounts();
    _db.execute("COMMIT");
    for (var comic in comics) {
      var hash = comic.id.hashCode ^ comic.type.value;
      _hashedIds.remove(hash);
      _syncCanonicalFavoriteDeleteIfOrphan(
        comicId: comic.id,
        type: ComicType(comic.type.value),
      );
      _runCanonicalSync((store) async {
        await store.deleteFavoriteFolderItemsByComic(
          _canonicalComicIdForFavorite(
            comicId: comic.id,
            type: ComicType(comic.type.value),
          ),
        );
      });
    }
    notifyListeners();
  }

  Future<int> removeInvalid() async {
    int count = 0;
    await Future.microtask(() {
      var all = allComics();
      for (var c in all) {
        var comicSource = c.type.comicSource;
        if ((c.type == ComicType.local &&
                legacyFindLocalComicByIdAndType(c.id, c.type) == null) ||
            (c.type != ComicType.local && comicSource == null)) {
          deleteComicWithId(c.folder, c.id, c.type);
          count++;
        }
      }
    });
    return count;
  }

  Future<void> clearAll() async {
    if (!_isInitialized) {
      return;
    }
    final folders = _getFolderNamesWithDB();
    for (final folder in folders) {
      _db.execute('DROP TABLE IF EXISTS "$folder";');
    }
    _db.execute('DELETE FROM folder_order;');
    _db.execute('DELETE FROM folder_sync;');
    counts.clear();
    _hashedIds.clear();
    _syncCanonicalFolderOrder(const <String>[]);
    notifyListeners();
  }

  void reorder(List<FavoriteItem> newFolder, String folder) async {
    if (!existsFolder(folder)) {
      throw Exception("Failed to reorder: folder not found");
    }
    _db.execute("BEGIN TRANSACTION");
    try {
      for (int i = 0; i < newFolder.length; i++) {
        _db.execute(
          """
          update "$folder"
          set display_order = ?
          where id == ? and type == ?;
        """,
          [i, newFolder[i].id, newFolder[i].type.value],
        );
      }
    } catch (e) {
      AppDiagnostics.error('favorites.batch', e, message: 'reorder_failed');
      _db.execute("ROLLBACK");
      return;
    }
    _db.execute("COMMIT");
    notifyListeners();
  }

  void rename(String before, String after) {
    if (existsFolder(after)) {
      throw "Name already exists!";
    }
    if (after.contains('"')) {
      throw "Invalid name";
    }
    _db.execute("""
      ALTER TABLE "$before"
      RENAME TO "$after";
    """);
    _db.execute(
      """
      update folder_order
      set folder_name = ?
      where folder_name == ?;
    """,
      [after, before],
    );
    _db.execute(
      """
      update folder_sync
      set folder_name = ?
      where folder_name == ?;
    """,
      [after, before],
    );
    counts[after] = counts[before] ?? 0;
    counts.remove(before);
    _syncCanonicalFolderRename(before: before, after: after);
    notifyListeners();
  }

  void onRead(String id, ComicType type) async {
    if (appdata.settings['moveFavoriteAfterRead'] == "none") {
      markAsRead(id, type);
      return;
    }
    var followUpdatesFolder = appdata.settings['followUpdatesFolder'];
    for (final folder in folderNames) {
      var rows = _db.select(
        """
        select * from "$folder"
        where id == ? and type == ?;
      """,
        [id, type.value],
      );
      if (rows.isNotEmpty) {
        var newTime = DateTime.now()
            .toIso8601String()
            .replaceFirst("T", " ")
            .substring(0, 19);
        String updateLocationSql = "";
        if (appdata.settings['moveFavoriteAfterRead'] == "end") {
          int maxValue =
              _db.select("""
            SELECT MAX(display_order) AS max_value
            FROM "$folder";
          """).firstOrNull?["max_value"] ??
              0;
          updateLocationSql = "display_order = ${maxValue + 1},";
        } else if (appdata.settings['moveFavoriteAfterRead'] == "start") {
          int minValue =
              _db.select("""
            SELECT MIN(display_order) AS min_value
            FROM "$folder";
          """).firstOrNull?["min_value"] ??
              0;
          updateLocationSql = "display_order = ${minValue - 1},";
        }
        _db.execute(
          """
            UPDATE "$folder"
            SET 
              $updateLocationSql
              ${followUpdatesFolder == folder ? "has_new_update = 0," : ""}
              time = ?
            WHERE id == ? and type == ?;
          """,
          [newTime, id, type.value],
        );
        if (followUpdatesFolder == folder) {
          updateFollowUpdatesUI();
        }
      }
    }
    notifyListeners();
  }

  List<FavoriteItem> searchInFolder(String folder, String keyword) {
    var keywordList = keyword.split(" ");
    keyword = keywordList.first;
    keyword = "%$keyword%";
    var res = _db.select(
      """
      SELECT * FROM "$folder" 
      WHERE name LIKE ? OR author LIKE ? OR tags LIKE ? OR translated_tags LIKE ?;
    """,
      [keyword, keyword, keyword, keyword],
    );
    var comics = res.map((e) => FavoriteItem.fromRow(e)).toList();
    bool test(FavoriteItem comic, String keyword) {
      if (comic.name.contains(keyword)) {
        return true;
      } else if (comic.author.contains(keyword)) {
        return true;
      } else if (comic.tags.any((element) => element.contains(keyword))) {
        return true;
      }
      return false;
    }

    for (var i = 1; i < keywordList.length; i++) {
      comics = comics
          .where((element) => test(element, keywordList[i]))
          .toList();
    }
    return comics;
  }

  List<FavoriteItem> search(String keyword) {
    var keywordList = keyword.split(" ");
    keyword = keywordList.first;
    var comics = <FavoriteItem>{};
    for (var table in folderNames) {
      keyword = "%$keyword%";
      var res = _db.select(
        """
        SELECT * FROM "$table" 
        WHERE name LIKE ? OR author LIKE ? OR tags LIKE ? OR translated_tags LIKE ?;
      """,
        [keyword, keyword, keyword, keyword],
      );
      for (var comic in res) {
        comics.add(FavoriteItem.fromRow(comic));
      }
      if (comics.length > 200) {
        break;
      }
    }

    bool test(FavoriteItem comic, String keyword) {
      keyword = keyword.trim();
      if (keyword.isEmpty) {
        return true;
      }
      if (comic.name.contains(keyword)) {
        return true;
      } else if (comic.author.contains(keyword)) {
        return true;
      } else if (comic.tags.any((element) => element.contains(keyword))) {
        return true;
      }
      return false;
    }

    return comics.where((element) {
      for (var i = 1; i < keywordList.length; i++) {
        if (!test(element, keywordList[i])) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void editTags(String id, String folder, List<String> tags) {
    _db.execute(
      """
        update "$folder"
        set tags = ?
        where id == ?;
      """,
      [tags.join(","), id],
    );
    notifyListeners();
  }

  bool isExist(String id, ComicType type) {
    var hash = id.hashCode ^ type.value;
    return _hashedIds.containsKey(hash);
  }

  void updateInfo(String folder, FavoriteItem comic, [bool notify = true]) {
    _db.execute(
      """
      update "$folder"
      set name = ?, author = ?, cover_path = ?, tags = ?
      where id == ? and type == ?;
    """,
      [
        comic.name,
        comic.author,
        comic.coverPath,
        comic.tags.join(","),
        comic.id,
        comic.type.value,
      ],
    );
    if (notify) {
      notifyListeners();
    }
  }

  String folderToJson(String folder) {
    var res = _db.select("""
      select * from "$folder";
    """);
    return jsonEncode({
      "info": "Generated by Venera",
      "name": folder,
      "comics": res.map((e) => FavoriteItem.fromRow(e).toJson()).toList(),
    });
  }

  void fromJson(String json) {
    var data = jsonDecode(json);
    var folder = data["name"];
    if (folder == null || folder is! String) {
      throw "Invalid data";
    }
    if (existsFolder(folder)) {
      int i = 0;
      while (existsFolder("$folder($i)")) {
        i++;
      }
      folder = "$folder($i)";
    }
    createFolder(folder);
    for (var comic in data["comics"]) {
      try {
        addComic(folder, FavoriteItem.fromJson(comic));
      } catch (e) {
        AppDiagnostics.error('favorites.import', e, message: 'import_data_failed');
      }
    }
  }

  void prepareTableForFollowUpdates(String table, [bool clearData = true]) {
    // check if the table has the column "last_update_time" "has_new_update" "last_check_time"
    var columns = _db.select("""
      pragma table_info("$table");
    """);
    if (!columns.any((element) => element["name"] == "last_update_time")) {
      _db.execute("""
        alter table "$table"
        add column last_update_time TEXT;
      """);
    }
    if (!columns.any((element) => element["name"] == "has_new_update")) {
      _db.execute("""
        alter table "$table"
        add column has_new_update int;
      """);
    }
    if (clearData) {
      _db.execute("""
        update "$table"
        set has_new_update = 0;
      """);
    }
    if (!columns.any((element) => element["name"] == "last_check_time")) {
      _db.execute("""
        alter table "$table"
        add column last_check_time int;
      """);
    }
  }

  void updateUpdateTime(
    String folder,
    String id,
    ComicType type,
    String updateTime,
  ) {
    var oldTime = _db
        .select(
          """
      select last_update_time from "$folder"
      where id == ? and type == ?;
    """,
          [id, type.value],
        )
        .first['last_update_time'];
    var hasNewUpdate = oldTime != updateTime;
    _db.execute(
      """
      update "$folder"
      set last_update_time = ?, has_new_update = ?, last_check_time = ?
      where id == ? and type == ?;
    """,
      [
        updateTime,
        hasNewUpdate ? 1 : 0,
        DateTime.now().millisecondsSinceEpoch,
        id,
        type.value,
      ],
    );
  }

  void updateCheckTime(String folder, String id, ComicType type) {
    _db.execute(
      """
      update "$folder"
      set last_check_time = ?
      where id == ? and type == ?;
    """,
      [DateTime.now().millisecondsSinceEpoch, id, type.value],
    );
  }

  int countUpdates(String folder) {
    return _db.select("""
      select count(*) as c from "$folder"
      where has_new_update == 1;
    """).first['c'];
  }

  List<FavoriteItemWithUpdateInfo> getUpdates(String folder) {
    if (!existsFolder(folder)) {
      return [];
    }
    var res = _db.select("""
      select * from "$folder"
      where has_new_update == 1;
    """);
    return res
        .map(
          (e) => FavoriteItemWithUpdateInfo(
            FavoriteItem.fromRow(e),
            e['last_update_time'],
            e['has_new_update'] == 1,
            e['last_check_time'],
          ),
        )
        .toList();
  }

  List<FavoriteItemWithUpdateInfo> getComicsWithUpdatesInfo(String folder) {
    if (!existsFolder(folder)) {
      return [];
    }
    var res = _db.select("""
      select * from "$folder";
    """);
    return res
        .map(
          (e) => FavoriteItemWithUpdateInfo(
            FavoriteItem.fromRow(e),
            e['last_update_time'],
            e['has_new_update'] == 1,
            e['last_check_time'],
          ),
        )
        .toList();
  }

  void markAsRead(String id, ComicType type) {
    final folder = appdata.settings['followUpdatesFolder'];
    if (folder is! String || folder.isEmpty) {
      return;
    }
    if (!existsFolder(folder)) {
      return;
    }
    _db.execute(
      """
      update "$folder"
      set has_new_update = 0
      where id == ? and type == ?;
    """,
      [id, type.value],
    );
  }

  Future<void> close() async {
    if (!_isInitialized) {
      return;
    }
    await _store.close();
    _db.dispose();
    _isInitialized = false;
  }

  void notifyChanges() {
    notifyListeners();
  }
}
