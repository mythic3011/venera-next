import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/widgets.dart' show ChangeNotifier;
import 'package:flutter_saf/flutter_saf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/local_metadata/local_metadata.dart';
import 'package:venera/foundation/reader/reader_open_target.dart';
import 'package:venera/network/download.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/utils/import_sort.dart';
import 'package:venera/utils/io.dart';

import 'app.dart';
import 'history.dart';

String localPageImageKey(File file) => file.uri.toString();

class LocalComic with HistoryMixin implements Comic {
  @override
  final String id;

  @override
  final String title;

  @override
  final String subtitle;

  @override
  final List<String> tags;

  /// The name of the directory where the comic is stored
  final String directory;

  /// key: chapter id, value: chapter title
  ///
  /// chapter id is the name of the directory in `LocalManager.path/$directory`
  final ComicChapters? chapters;

  bool get hasChapters => chapters != null;

  /// relative path to the cover image
  @override
  final String cover;

  final ComicType comicType;

  final List<String> downloadedChapters;

  final DateTime createdAt;

  const LocalComic({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.directory,
    required this.chapters,
    required this.cover,
    required this.comicType,
    required this.downloadedChapters,
    required this.createdAt,
  });

  LocalComic.fromRow(Row row)
      : id = row[0] as String,
        title = row[1] as String,
        subtitle = row[2] as String,
        tags = List.from(jsonDecode(row[3] as String)),
        directory = row[4] as String,
        chapters = ComicChapters.fromJsonOrNull(jsonDecode(row[5] as String)),
        cover = row[6] as String,
        comicType = ComicType(row[7] as int),
        downloadedChapters = List.from(jsonDecode(row[8] as String)),
        createdAt = DateTime.fromMillisecondsSinceEpoch(row[9] as int);

  File get coverFile => File(FilePath.join(
        baseDir,
        cover,
      ));

  String get baseDir => (directory.contains('/') || directory.contains('\\'))
      ? directory
      : FilePath.join(LocalManager().path, directory);

  @override
  String get description => "";

  @override
  String get sourceKey =>
      comicType == ComicType.local ? "local" : comicType.sourceKey;

  @override
  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "cover": cover,
      "id": id,
      "subTitle": subtitle,
      "tags": tags,
      "description": description,
      "sourceKey": sourceKey,
      "chapters": chapters?.toJson(),
    };
  }

  @override
  int? get maxPage => null;

  void read() async {
    try {
      await LocalComicCanonicalSyncService(
        store: App.unifiedComicsStore,
      ).syncComic(this);
    } catch (error) {
      App.rootContext.showMessage(message: error.toString());
      return;
    }
    var history = HistoryManager().find(id, comicType);
    int? firstDownloadedChapter;
    int? firstDownloadedChapterGroup;
    if (downloadedChapters.isNotEmpty && chapters != null) {
      final chapters = this.chapters!;
      if (chapters.isGrouped) {
        for (int i=0; i<chapters.groupCount; i++) {
          var group = chapters.getGroupByIndex(i);
          var keys = group.keys.toList();
          for (int j=0; j<keys.length; j++) {
            var chapterId = keys[j];
            if (downloadedChapters.contains(chapterId)) {
              firstDownloadedChapter = j + 1;
              firstDownloadedChapterGroup = i + 1;
              break;
            }
          }
        }
      } else {
        var keys = chapters.allChapters.keys;
        for (int i = 0; i < keys.length; i++) {
          if (downloadedChapters.contains(keys.elementAt(i))) {
            firstDownloadedChapter = i + 1;
            break;
          }
        }
      }
    }
    final sourceRef = resolveReaderTargetSourceRef(
      comicId: id,
      sourceKey: comicType.sourceKey,
      chapters: chapters,
      ep: history?.ep ?? firstDownloadedChapter,
      group: history?.group ?? firstDownloadedChapterGroup,
      resumeSourceRef: HistoryManager().findResumeSourceRef(id, comicType),
    );
    App.rootContext.to(
      () => Reader(
        type: comicType,
        cid: id,
        name: title,
        chapters: chapters,
        initialChapter: history?.ep ?? firstDownloadedChapter,
        initialPage: history?.page,
        initialChapterGroup: history?.group ?? firstDownloadedChapterGroup,
        history: history ?? History.fromModel(model: this, ep: 0, page: 0),
        sourceRef: sourceRef,
        author: subtitle,
        tags: tags,
      )
    );
  }

  @override
  HistoryType get historyType => comicType;

  @override
  String? get subTitle => subtitle;

  @override
  String? get language => null;

  @override
  String? get favoriteId => null;

  @override
  double? get stars => null;
}

class LocalManager with ChangeNotifier {
  static LocalManager? _instance;

  LocalManager._();

  factory LocalManager() {
    return _instance ??= LocalManager._();
  }

  late Database _db;
  late LocalMetadataRepository _metadataRepository;

  /// path to the directory where all the comics are stored
  late String path;

  Directory get directory => Directory(path);

  void _checkNoMedia() {
    if (App.isAndroid) {
      var file = File(FilePath.join(path, '.nomedia'));
      if (!file.existsSync()) {
        file.createSync();
      }
    }
  }

  // return error message if failed
  Future<String?> setNewPath(String newPath) async {
    var newDir = Directory(newPath);
    if (!await newDir.exists()) {
      return "Directory does not exist";
    }
    if (!await newDir.list().isEmpty) {
      return "Directory is not empty";
    }
    try {
      await copyDirectoryIsolate(
        directory,
        newDir,
      );
      await File(FilePath.join(App.dataPath, 'local_path'))
          .writeAsString(newPath);
    } catch (e, s) {
      Log.error("IO", e, s);
      return e.toString();
    }
    await directory.deleteContents(recursive: true);
    path = newPath;
    _checkNoMedia();
    return null;
  }

  Future<String> findDefaultPath() async {
    if (App.isAndroid) {
      var external = await getExternalStorageDirectories();
      if (external != null && external.isNotEmpty) {
        return FilePath.join(external.first.path, 'local');
      } else {
        return FilePath.join(App.dataPath, 'local');
      }
    } else if (App.isIOS) {
      var oldPath = FilePath.join(App.dataPath, 'local');
      if (Directory(oldPath).existsSync() &&
          Directory(oldPath).listSync().isNotEmpty) {
        return oldPath;
      } else {
        var directory = await getApplicationDocumentsDirectory();
        return FilePath.join(directory.path, 'local');
      }
    } else {
      return FilePath.join(App.dataPath, 'local');
    }
  }

  Future<void> _checkPathValidation() async {
    var testFile = File(FilePath.join(path, 'venera_test'));
    try {
      testFile.createSync();
      testFile.deleteSync();
    } catch (e) {
      Log.error("IO",
          "Failed to create test file in local path: $e\nUsing default path instead.");
      path = await findDefaultPath();
    }
  }

  Future<void> init({bool skipSourceInit = false}) async {
    _db = sqlite3.open(
      '${App.dataPath}/local.db',
    );
    _db.execute('''
      CREATE TABLE IF NOT EXISTS comics (
        id TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT NOT NULL,
        tags TEXT NOT NULL,
        directory TEXT NOT NULL,
        chapters TEXT NOT NULL,
        cover TEXT NOT NULL,
        comic_type INTEGER NOT NULL,
        downloadedChapters TEXT NOT NULL,
        created_at INTEGER,
        PRIMARY KEY (id, comic_type)
      );
    ''');
    if (File(FilePath.join(App.dataPath, 'local_path')).existsSync()) {
      path = File(FilePath.join(App.dataPath, 'local_path')).readAsStringSync();
      if (!directory.existsSync()) {
        path = await findDefaultPath();
      }
    } else {
      path = await findDefaultPath();
    }
    try {
      if (!directory.existsSync()) {
        await directory.create();
      }
    } catch (e, s) {
      Log.error("IO", "Failed to create local folder: $e", s);
    }
    _checkPathValidation();
    _checkNoMedia();
    _metadataRepository = LocalMetadataRepository(
      FilePath.join(App.dataPath, 'local_metadata_v1.json'),
    );
    await _metadataRepository.init();
    if (!skipSourceInit) {
      await ComicSourceManager().ensureInit();
    }
    restoreDownloadingTasks();
  }


  String _metadataSeriesKey(LocalComic comic) {
    return '${comic.comicType.value}:${comic.id}';
  }

  String? _normalizeMetadataGroupId(String? groupId) {
    final trimmed = groupId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed == "__default__") {
      return LocalSeriesMeta.defaultGroupId;
    }
    return trimmed;
  }

  bool _metadataGroupExists(LocalSeriesMeta series, String? groupId) {
    return groupId == null ||
        groupId == LocalSeriesMeta.defaultGroupId ||
        series.groups.any((group) => group.id == groupId);
  }

  bool _metadataGroupLabelExists(
    Iterable<LocalChapterGroup> groups,
    String label, {
    String? exceptGroupId,
  }) {
    return groups.any((group) {
      return group.id != exceptGroupId && group.label == label;
    });
  }

  void setMetadataRepositoryForTest(LocalMetadataRepository repository) {
    _metadataRepository = repository;
  }

  Future<void> createGroup(
    LocalComic comic, {
    required String label,
    String? groupId,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) {
      throw Exception('Group label cannot be empty');
    }
    final seriesKey = _metadataSeriesKey(comic);
    final existing = _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(seriesKey: seriesKey, groups: const [], chapters: const {});
    final groups = existing.groups.toList();
    if (_metadataGroupLabelExists(groups, normalizedLabel)) {
      throw Exception("Group label already exists");
    }
    final id = (groupId?.trim().isNotEmpty ?? false)
        ? _normalizeMetadataGroupId(groupId)!
        : 'group_${DateTime.now().microsecondsSinceEpoch}';
    if (groups.any((g) => g.id == id)) {
      throw Exception('Group already exists');
    }
    final maxSortOrder = groups.isEmpty
        ? -1
        : groups.map((g) => g.sortOrder).reduce((a, b) => a > b ? a : b);
    groups.add(
      LocalChapterGroup(
        id: id,
        label: normalizedLabel,
        sortOrder: maxSortOrder + 1,
      ),
    );
    await _metadataRepository.upsertSeries(existing.copyWith(groups: groups));
  }

  Future<void> renameGroup(
    LocalComic comic, {
    required String groupId,
    required String newLabel,
  }) async {
    final normalizedLabel = newLabel.trim();
    if (normalizedLabel.isEmpty) {
      throw Exception('Group label cannot be empty');
    }
    final seriesKey = _metadataSeriesKey(comic);
    final existing = _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(seriesKey: seriesKey, groups: const [], chapters: const {});
    if (_metadataGroupLabelExists(
      existing.groups,
      normalizedLabel,
      exceptGroupId: groupId,
    )) {
      throw Exception("Group label already exists");
    }
    var found = false;
    final groups = existing.groups.map((group) {
      if (group.id != groupId) return group;
      found = true;
      return LocalChapterGroup(
        id: group.id,
        label: normalizedLabel,
        sortOrder: group.sortOrder,
      );
    }).toList();
    if (!found) {
      throw Exception('Group not found');
    }
    await _metadataRepository.upsertSeries(existing.copyWith(groups: groups));
  }

  Future<void> reorderGroups(LocalComic comic, List<String> orderedGroupIds) async {
    final seriesKey = _metadataSeriesKey(comic);
    final existing = _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(seriesKey: seriesKey, groups: const [], chapters: const {});
    final groupsById = {for (final group in existing.groups) group.id: group};
    if (orderedGroupIds.toSet().length != orderedGroupIds.length ||
        groupsById.length != orderedGroupIds.length ||
        !orderedGroupIds.every(groupsById.containsKey)) {
      throw Exception('Invalid group order');
    }
    final reordered = <LocalChapterGroup>[];
    for (var i = 0; i < orderedGroupIds.length; i++) {
      final current = groupsById[orderedGroupIds[i]]!;
      reordered.add(
        LocalChapterGroup(id: current.id, label: current.label, sortOrder: i),
      );
    }
    await _metadataRepository.upsertSeries(existing.copyWith(groups: reordered));
  }

  Future<void> assignChapterToGroup(
    LocalComic comic, {
    required String chapterId,
    String? groupId,
  }) async {
    final chapterMap = comic.chapters?.allChapters;
    if (chapterMap == null || !chapterMap.containsKey(chapterId)) {
      throw Exception('Chapter not found');
    }
    final seriesKey = _metadataSeriesKey(comic);
    final existing = _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(seriesKey: seriesKey, groups: const [], chapters: const {});
    final normalizedGroupId = _normalizeMetadataGroupId(groupId);
    if (!_metadataGroupExists(existing, normalizedGroupId)) {
      throw Exception('Group not found');
    }
    final chapters = Map<String, LocalChapterMeta>.from(existing.chapters);
    final current = chapters[chapterId];
    chapters[chapterId] = LocalChapterMeta(
      chapterId: chapterId,
      displayTitle: current?.displayTitle,
      groupId: normalizedGroupId,
      sortOrder: current?.sortOrder,
    );
    await _metadataRepository.upsertSeries(existing.copyWith(chapters: chapters));
  }

  Future<void> renameChapter(
    LocalComic comic, {
    required String chapterId,
    required String newTitle,
  }) async {
    final normalizedTitle = newTitle.trim();
    final chapterMap = comic.chapters?.allChapters;
    if (normalizedTitle.isEmpty) {
      throw Exception('Chapter title cannot be empty');
    }
    if (chapterMap == null || !chapterMap.containsKey(chapterId)) {
      throw Exception('Chapter not found');
    }
    final seriesKey = _metadataSeriesKey(comic);
    final existing = _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(seriesKey: seriesKey, groups: const [], chapters: const {});
    final chapters = Map<String, LocalChapterMeta>.from(existing.chapters);
    final current = chapters[chapterId];
    chapters[chapterId] = LocalChapterMeta(
      chapterId: chapterId,
      displayTitle: normalizedTitle,
      groupId: current?.groupId,
      sortOrder: current?.sortOrder,
    );
    await _metadataRepository.upsertSeries(existing.copyWith(chapters: chapters));
  }

  Future<void> reorderChapters(
    LocalComic comic, {
    required String groupId,
    required List<String> orderedChapterIds,
  }) async {
    final chapterMap = comic.chapters?.allChapters;
    if (chapterMap == null) {
      throw Exception('Comic does not have chapters');
    }
    final knownIds = chapterMap.keys.toSet();
    if (orderedChapterIds.toSet().length != orderedChapterIds.length ||
        !orderedChapterIds.every(knownIds.contains)) {
      throw Exception('Invalid chapter order');
    }
    final seriesKey = _metadataSeriesKey(comic);
    final existing = _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(seriesKey: seriesKey, groups: const [], chapters: const {});
    final normalizedGroupId = _normalizeMetadataGroupId(groupId);
    if (!_metadataGroupExists(existing, normalizedGroupId)) {
      throw Exception("Group not found");
    }
    final chapters = Map<String, LocalChapterMeta>.from(existing.chapters);
    for (var i = 0; i < orderedChapterIds.length; i++) {
      final chapterId = orderedChapterIds[i];
      final current = chapters[chapterId];
      chapters[chapterId] = LocalChapterMeta(
        chapterId: chapterId,
        displayTitle: current?.displayTitle,
        groupId: normalizedGroupId,
        sortOrder: i,
      );
    }
    await _metadataRepository.upsertSeries(existing.copyWith(chapters: chapters));
  }

  EffectiveChaptersView? readEffectiveChapters(LocalComic comic) {
    final base = comic.chapters;
    if (base == null) return null;
    final series = _metadataRepository.getSeries(_metadataSeriesKey(comic));
    if (series == null) {
      final fallback = <String, Map<String, String>>{};
      fallback[LocalSeriesMeta.defaultGroupLabel] =
          LinkedHashMap<String, String>.from(base.allChapters);
      return EffectiveChaptersView(groupedChapters: fallback);
    }

    final grouped = <String, Map<String, String>>{};
    final allBase = base.allChapters;
    final chaptersByGroup = <String, List<(String, String, int)>>{};

    var fallbackOrder = 100000;
    for (final entry in allBase.entries) {
      final chapterId = entry.key;
      final chapterTitle = entry.value;
      final meta = series.chapters[chapterId];
      final requestedGroupId = _normalizeMetadataGroupId(meta?.groupId);
      final hasRequestedGroup = _metadataGroupExists(series, requestedGroupId);
      final targetGroupId = hasRequestedGroup
          ? (requestedGroupId ?? LocalSeriesMeta.defaultGroupId)
          : LocalSeriesMeta.defaultGroupId;
      final effectiveTitle = meta?.displayTitle ?? chapterTitle;
      final sortOrder = meta?.sortOrder ?? fallbackOrder++;
      chaptersByGroup.putIfAbsent(targetGroupId, () => []);
      chaptersByGroup[targetGroupId]!.add((chapterId, effectiveTitle, sortOrder));
    }

    final availableGroups = <LocalChapterGroup>[
      ...series.groups,
      if (!series.groups.any((g) => g.id == LocalSeriesMeta.defaultGroupId))
        const LocalChapterGroup(
          id: LocalSeriesMeta.defaultGroupId,
          label: LocalSeriesMeta.defaultGroupLabel,
          sortOrder: -1,
        ),
    ]..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.id.compareTo(b.id);
      });

    for (final group in availableGroups) {
      final rows = chaptersByGroup[group.id];
      if (rows == null || rows.isEmpty) {
        continue;
      }
      rows.sort((a, b) {
        final byOrder = a.$3.compareTo(b.$3);
        if (byOrder != 0) return byOrder;
        return a.$1.compareTo(b.$1);
      });
      final mapped = <String, String>{};
      for (final row in rows) {
        mapped[row.$1] = row.$2;
      }
      final existingGroup = grouped[group.label];
      if (existingGroup == null) {
        grouped[group.label] = mapped;
      } else {
        existingGroup.addAll(mapped);
      }
    }

    if (grouped.isEmpty) {
      grouped[LocalSeriesMeta.defaultGroupLabel] =
          LinkedHashMap<String, String>.from(allBase);
    }
    return EffectiveChaptersView(groupedChapters: grouped);
  }
  String findValidId(ComicType type) {
    final res = _db.select(
      '''
      SELECT id FROM comics WHERE comic_type = ?
      ORDER BY CAST(id AS INTEGER) DESC
      LIMIT 1;
      ''',
      [type.value],
    );
    if (res.isEmpty) {
      return '1';
    }
    return (int.parse((res.first[0])) + 1).toString();
  }

  Future<void> add(LocalComic comic, [String? id]) async {
    var old = find(id ?? comic.id, comic.comicType);
    var downloaded = comic.downloadedChapters;
    if (old != null) {
      downloaded.addAll(old.downloadedChapters);
    }
    _db.execute(
      'INSERT OR REPLACE INTO comics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id ?? comic.id,
        comic.title,
        comic.subtitle,
        jsonEncode(comic.tags),
        comic.directory,
        jsonEncode(comic.chapters),
        comic.cover,
        comic.comicType.value,
        jsonEncode(downloaded),
        comic.createdAt.millisecondsSinceEpoch,
      ],
    );
    notifyListeners();
  }

  void remove(String id, ComicType comicType) async {
    _db.execute(
      'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
      [id, comicType.value],
    );
    notifyListeners();
  }

  void removeComic(LocalComic comic) {
    remove(comic.id, comic.comicType);
    notifyListeners();
  }

  List<LocalComic> getComics(LocalSortType sortType) {
    var res = _db.select('''
      SELECT * FROM comics
      ORDER BY
        ${sortType.value == 'name' ? 'title' : 'created_at'}
        ${sortType.value == 'time_asc' ? 'ASC' : 'DESC'}
      ;
    ''');
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  LocalComic? find(String id, ComicType comicType) {
    final res = _db.select(
      'SELECT * FROM comics WHERE id = ? AND comic_type = ?;',
      [id, comicType.value],
    );
    if (res.isEmpty) {
      return null;
    }
    return LocalComic.fromRow(res.first);
  }

  @override
  void dispose() {
    super.dispose();
    _db.dispose();
  }

  List<LocalComic> getRecent() {
    final res = _db.select('''
      SELECT * FROM comics
      ORDER BY created_at DESC
      LIMIT 20;
    ''');
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  int get count {
    final res = _db.select('''
      SELECT COUNT(*) FROM comics;
    ''');
    return res.first[0] as int;
  }

  LocalComic? findByName(String name) {
    final res = _db.select('''
      SELECT * FROM comics
      WHERE title = ? OR directory = ?;
    ''', [name, name]);
    if (res.isEmpty) {
      return null;
    }
    return LocalComic.fromRow(res.first);
  }

  List<LocalComic> search(String keyword) {
    final res = _db.select('''
      SELECT * FROM comics
      WHERE title LIKE ? OR tags LIKE ? OR subtitle LIKE ?
      ORDER BY created_at DESC;
    ''', ['%$keyword%', '%$keyword%', '%$keyword%']);
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  Future<List<String>> getImages(String id, ComicType type, Object ep) async {
    if (ep is! String && ep is! int) {
      throw "Invalid ep";
    }
    var comic = find(id, type) ?? (throw "Comic Not Found");
    var directory = Directory(comic.baseDir);
    if (comic.hasChapters) {
      var cid =
          ep is int ? comic.chapters!.ids.elementAt(ep - 1) : (ep as String);
      cid = getChapterDirectoryName(cid);
      directory = Directory(FilePath.join(directory.path, cid));
    }
    var files = <File>[];
    await for (var entity in directory.list()) {
      if (entity is File) {
        // Do not exclude comic.cover, since it may be the first page of the chapter.
        // A file with name starting with 'cover.' is not a comic page.
        if (entity.name.startsWith('cover.')) {
          continue;
        }
        //Hidden file in some file system
        if (entity.name.startsWith('.')) {
          continue;
        }
        files.add(entity);
      }
    }
    files.sort((a, b) {
      return naturalCompare(a.name, b.name);
    });
    return files.map(localPageImageKey).toList();
  }

  Future<void> reorderComicPages(
      LocalComic comic, Object ep, List<String> orderedFileNames) async {
    if (!comic.baseDir.startsWith(path)) {
      throw Exception("Only app-managed local comics support page reorder");
    }
    if (ep is! int && ep is! String) {
      throw Exception("Invalid chapter");
    }
    var chapterDir = Directory(comic.baseDir);
    if (comic.hasChapters) {
      final chapterId = ep is int
          ? comic.chapters!.ids.elementAt(ep - 1)
          : ep as String;
      chapterDir = Directory(
        FilePath.join(comic.baseDir, getChapterDirectoryName(chapterId)),
      );
    }
    if (!chapterDir.existsSync()) {
      throw Exception("Chapter directory not found");
    }

    final sourceFiles = chapterDir
        .listSync()
        .whereType<File>()
        .where((f) =>
            !f.name.startsWith('cover.') &&
            !f.name.startsWith('.') &&
            !isHiddenOrMacMetadataPath(f.name))
        .toList();
    if (sourceFiles.isEmpty) {
      return;
    }

    final names = sourceFiles.map((e) => e.name).toSet();
    if (orderedFileNames.length != sourceFiles.length ||
        orderedFileNames.toSet().length != orderedFileNames.length ||
        !orderedFileNames.every(names.contains)) {
      throw Exception("Invalid page list");
    }

    final tempFiles = <String>[];
    for (var i = 0; i < orderedFileNames.length; i++) {
      final original = File(FilePath.join(chapterDir.path, orderedFileNames[i]));
      final tempName = "__reorder_tmp__$i.${original.extension}";
      final tempPath = FilePath.join(chapterDir.path, tempName);
      await original.rename(tempPath);
      tempFiles.add(tempPath);
    }
    for (var i = 0; i < tempFiles.length; i++) {
      final temp = File(tempFiles[i]);
      final targetPath = FilePath.join(chapterDir.path, "${i + 1}.${temp.extension}");
      await temp.rename(targetPath);
    }
  }

  bool isDownloaded(String id, ComicType type,
      [int? ep, ComicChapters? chapters]) {
    var comic = find(id, type);
    if (comic == null) return false;
    if (comic.chapters == null || ep == null) return true;
    if (chapters != null) {
      if (comic.chapters?.length != chapters.length) {
        // update
        add(LocalComic(
          id: comic.id,
          title: comic.title,
          subtitle: comic.subtitle,
          tags: comic.tags,
          directory: comic.directory,
          chapters: chapters,
          cover: comic.cover,
          comicType: comic.comicType,
          downloadedChapters: comic.downloadedChapters,
          createdAt: comic.createdAt,
        ));
      }
    }
    return comic.downloadedChapters
        .contains((chapters ?? comic.chapters)!.ids.elementAtOrNull(ep - 1));
  }

  List<DownloadTask> downloadingTasks = [];

  bool isDownloading(String id, ComicType type) {
    return downloadingTasks
        .any((element) => element.id == id && element.comicType == type);
  }

  Future<Directory> findValidDirectory(
      String id, ComicType type, String name) async {
    var comic = find(id, type);
    if (comic != null) {
      return Directory(FilePath.join(path, comic.directory));
    }
    const comicDirectoryMaxLength = 80;
    if (name.length > comicDirectoryMaxLength) {
      name = name.substring(0, comicDirectoryMaxLength);
    }
    var dir = findValidDirectoryName(path, name);
    return Directory(FilePath.join(path, dir)).create().then((value) => value);
  }

  void completeTask(DownloadTask task) {
    add(task.toLocalComic());
    downloadingTasks.remove(task);
    notifyListeners();
    saveCurrentDownloadingTasks();
    downloadingTasks.firstOrNull?.resume();
  }

  void removeTask(DownloadTask task) {
    downloadingTasks.remove(task);
    notifyListeners();
    saveCurrentDownloadingTasks();
  }

  void moveToFirst(DownloadTask task) {
    if (downloadingTasks.first != task) {
      var shouldResume = !downloadingTasks.first.isPaused;
      downloadingTasks.first.pause();
      downloadingTasks.remove(task);
      downloadingTasks.insert(0, task);
      notifyListeners();
      saveCurrentDownloadingTasks();
      if (shouldResume) {
        downloadingTasks.first.resume();
      }
    }
  }

  Future<void> saveCurrentDownloadingTasks() async {
    var tasks = downloadingTasks.map((e) => e.toJson()).toList();
    await File(FilePath.join(App.dataPath, 'downloading_tasks.json'))
        .writeAsString(jsonEncode(tasks));
  }

  void restoreDownloadingTasks() {
    var file = File(FilePath.join(App.dataPath, 'downloading_tasks.json'));
    if (file.existsSync()) {
      try {
        var tasks = jsonDecode(file.readAsStringSync());
        for (var e in tasks) {
          var task = DownloadTask.fromJson(e);
          if (task != null) {
            downloadingTasks.add(task);
          }
        }
      } catch (e) {
        file.delete();
        Log.error("LocalManager", "Failed to restore downloading tasks: $e");
      }
    }
  }

  void addTask(DownloadTask task) {
    downloadingTasks.add(task);
    notifyListeners();
    saveCurrentDownloadingTasks();
    downloadingTasks.first.resume();
  }

  Future<void> setComicCover(LocalComic comic, String imagePath) async {
    if (!comic.baseDir.startsWith(path)) {
      throw Exception("Only app-managed local comics support setting cover");
    }
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      throw Exception("Cover image not found");
    }
    if (!imageFile.path.startsWith(comic.baseDir)) {
      throw Exception("Invalid cover image path");
    }
    final ext = imageFile.extension;
    final newCoverName = "cover.$ext";
    final newCoverPath = FilePath.join(comic.baseDir, newCoverName);
    await imageFile.copy(newCoverPath);
    if (comic.cover != newCoverName) {
      final oldCover = File(FilePath.join(comic.baseDir, comic.cover));
      if (oldCover.existsSync()) {
        oldCover.deleteIgnoreError();
      }
      _db.execute(
        'UPDATE comics SET cover = ? WHERE id = ? AND comic_type = ?;',
        [newCoverName, comic.id, comic.comicType.value],
      );
    }
    notifyListeners();
  }

  void deleteComic(LocalComic c, [bool removeFileOnDisk = true]) {
    if (removeFileOnDisk) {
      var dir = Directory(FilePath.join(path, c.directory));
      dir.deleteIgnoreError(recursive: true);
    }
    // Deleting a local comic means that it's no longer available, thus both favorite and history should be deleted.
    if (c.comicType == ComicType.local) {
      if (HistoryManager().isInitialized) {
        if (HistoryManager().find(c.id, c.comicType) != null) {
          HistoryManager().remove(c.id, c.comicType);
        }
      }
      LocalFavoritesManager().deleteLocalComicFromAllFoldersIfInitialized(
        c.id,
        c.comicType,
      );
    }
    remove(c.id, c.comicType);
    _metadataRepository.removeSeries(_metadataSeriesKey(c));
    notifyListeners();
  }

  void deleteComicChapters(LocalComic c, List<String> chapters) {
    if (chapters.isEmpty) {
      return;
    }
    var newDownloadedChapters = c.downloadedChapters
        .where((e) => !chapters.contains(e))
        .toList();
    if (newDownloadedChapters.isNotEmpty) {
      final currentMap = c.chapters?.allChapters ?? const <String, String>{};
      final newChapterMap = <String, String>{};
      for (final id in newDownloadedChapters) {
        final title = currentMap[id];
        if (title != null) {
          newChapterMap[id] = title;
        }
      }
      _db.execute(
        'UPDATE comics SET chapters = ?, downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
        [
          jsonEncode(newChapterMap),
          jsonEncode(newDownloadedChapters),
          c.id,
          c.comicType.value,
        ],
      );
      _removeChapterMetadata(c, chapters);
    } else {
      _db.execute(
        'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
        [c.id, c.comicType.value],
      );
      _metadataRepository.removeSeries(_metadataSeriesKey(c));
    }
    var shouldRemovedDirs = <Directory>[];
    for (var chapter in chapters) {
      var dir = Directory(FilePath.join(
        c.baseDir,
        getChapterDirectoryName(chapter),
      ));
      if (dir.existsSync()) {
        shouldRemovedDirs.add(dir);
      }
    }
    if (shouldRemovedDirs.isNotEmpty) {
      _deleteDirectories(shouldRemovedDirs);
    }
    notifyListeners();
  }

  Future<void> _removeChapterMetadata(
    LocalComic comic,
    Iterable<String> chapterIds,
  ) async {
    final series = _metadataRepository.getSeries(_metadataSeriesKey(comic));
    if (series == null) return;
    final removeIds = chapterIds.toSet();
    final chapters = Map<String, LocalChapterMeta>.from(series.chapters)
      ..removeWhere((id, _) => removeIds.contains(id));
    await _metadataRepository.upsertSeries(series.copyWith(chapters: chapters));
  }

  void renameComicChapter(LocalComic comic, String chapterId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final currentMap = comic.chapters?.allChapters;
    if (currentMap == null || !currentMap.containsKey(chapterId)) {
      throw Exception("Chapter not found");
    }
    final updated = LinkedHashMap<String, String>.from(currentMap);
    updated[chapterId] = trimmed;
    _db.execute(
      'UPDATE comics SET chapters = ? WHERE id = ? AND comic_type = ?;',
      [jsonEncode(updated), comic.id, comic.comicType.value],
    );
    notifyListeners();
  }

  void reorderComicChapters(LocalComic comic, List<String> orderedChapterIds) {
    final currentDownloaded = comic.downloadedChapters.toSet();
    final orderedSet = orderedChapterIds.toSet();
    if (orderedChapterIds.length != comic.downloadedChapters.length ||
        orderedSet.length != orderedChapterIds.length ||
        currentDownloaded.length != orderedSet.length ||
        !orderedSet.containsAll(currentDownloaded)) {
      throw Exception("Invalid chapter order");
    }
    final currentMap = comic.chapters?.allChapters ?? const <String, String>{};
    final reordered = <String, String>{};
    for (final id in orderedChapterIds) {
      reordered[id] = currentMap[id] ?? id;
    }
    _db.execute(
      'UPDATE comics SET chapters = ?, downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
      [
        jsonEncode(reordered),
        jsonEncode(orderedChapterIds),
        comic.id,
        comic.comicType.value,
      ],
    );
    notifyListeners();
  }

  Future<void> addComicsAsChapters(
    LocalComic targetComic,
    List<LocalComic> sourceComics, {
    bool deleteSourceComics = false,
  }) async {
    if (sourceComics.isEmpty) return;
    final target = find(targetComic.id, targetComic.comicType);
    if (target == null) {
      throw Exception("Target comic not found");
    }
    if (!target.baseDir.startsWith(path)) {
      throw Exception("Only app-managed local comics support chapter merge");
    }

    final targetDir = Directory(target.baseDir);
    if (!targetDir.existsSync()) {
      throw Exception("Target comic directory not found");
    }

    final chapterMap = <String, String>{};
    final downloaded = <String>[];

    if (target.hasChapters) {
      final all = target.chapters!.allChapters;
      for (final id in target.downloadedChapters) {
        chapterMap[id] = all[id] ?? id;
        downloaded.add(id);
      }
    } else {
      final existingPages = await _listChapterImageFiles(targetDir);
      if (existingPages.isNotEmpty) {
        const id = "1";
        final chapterDir = Directory(
          FilePath.join(targetDir.path, getChapterDirectoryName(id)),
        );
        chapterDir.createSync(recursive: true);
        await _copyPagesToChapter(existingPages, chapterDir);
        for (final page in existingPages) {
          page.deleteIgnoreError();
        }
        chapterMap[id] = target.title;
        downloaded.add(id);
      }
    }

    var nextId = _computeNextChapterId(chapterMap.keys);
    final shouldDeleteSources = <LocalComic>[];

    for (final sourceItem in sourceComics) {
      final source = find(sourceItem.id, sourceItem.comicType);
      if (source == null || source.id == target.id) continue;

      Future<void> appendOneChapter(Directory sourceDir, String sourceTitle) async {
        final pages = await _listChapterImageFiles(sourceDir);
        if (pages.isEmpty) return;
        final chapterId = (nextId++).toString();
        final chapterDir = Directory(
          FilePath.join(targetDir.path, getChapterDirectoryName(chapterId)),
        );
        chapterDir.createSync(recursive: true);
        await _copyPagesToChapter(pages, chapterDir);
        chapterMap[chapterId] = sourceTitle;
        downloaded.add(chapterId);
      }

      if (source.hasChapters) {
        final all = source.chapters!.allChapters;
        for (final chapterId in source.downloadedChapters) {
          final chapterTitle = all[chapterId] ?? chapterId;
          final sourceDir = Directory(
            FilePath.join(source.baseDir, getChapterDirectoryName(chapterId)),
          );
          if (!sourceDir.existsSync()) continue;
          await appendOneChapter(sourceDir, "${source.title} - $chapterTitle");
        }
      } else {
        final sourceDir = Directory(source.baseDir);
        if (sourceDir.existsSync()) {
          await appendOneChapter(sourceDir, source.title);
        }
      }

      if (deleteSourceComics) {
        shouldDeleteSources.add(source);
      }
    }

    if (downloaded.isEmpty) {
      return;
    }

    _db.execute(
      'UPDATE comics SET chapters = ?, downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
      [
        jsonEncode(chapterMap),
        jsonEncode(downloaded),
        target.id,
        target.comicType.value,
      ],
    );

    if (deleteSourceComics && shouldDeleteSources.isNotEmpty) {
      batchDeleteComics(shouldDeleteSources, true, true);
      return;
    }
    notifyListeners();
  }

  int _computeNextChapterId(Iterable<String> ids) {
    var maxId = 0;
    for (final id in ids) {
      final n = int.tryParse(id);
      if (n != null && n > maxId) {
        maxId = n;
      }
    }
    return maxId + 1;
  }

  Future<List<File>> _listChapterImageFiles(Directory dir) async {
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (entity.name.startsWith('cover.')) continue;
      if (entity.name.startsWith('.')) continue;
      if (isHiddenOrMacMetadataPath(entity.name)) continue;
      files.add(entity);
    }
    files.sort((a, b) => naturalCompare(a.name, b.name));
    return files;
  }

  Future<void> _copyPagesToChapter(
    List<File> sourceFiles,
    Directory chapterDir,
  ) async {
    for (var i = 0; i < sourceFiles.length; i++) {
      final source = sourceFiles[i];
      final target = File(
        FilePath.join(chapterDir.path, "${i + 1}.${source.extension}"),
      );
      await source.copy(target.path);
    }
  }

  void batchDeleteComics(List<LocalComic> comics, [bool removeFileOnDisk = true, bool removeFavoriteAndHistory = true]) {
    if (comics.isEmpty) {
      return;
    }

    var shouldRemovedDirs = <Directory>[];
    _db.execute('BEGIN TRANSACTION;');
    try {
      for (var c in comics) {
        if (removeFileOnDisk) {
          var dir = Directory(FilePath.join(path, c.directory));
          if (dir.existsSync()) {
            shouldRemovedDirs.add(dir);
          }
        }
        _db.execute(
          'DELETE FROM comics WHERE id = ? AND comic_type = ?;',
          [c.id, c.comicType.value],
        );
      }
    }
    catch(e, s) {
      Log.error("LocalManager", "Failed to batch delete comics: $e", s);
      _db.execute('ROLLBACK;');
      return;
    }
    _db.execute('COMMIT;');

    var comicIDs = comics.map((e) => ComicID(e.comicType, e.id)).toList();

    if (removeFavoriteAndHistory) {
      LocalFavoritesManager().batchDeleteComicsInAllFolders(comicIDs);
      HistoryManager().batchDeleteHistories(comicIDs);
    }

    notifyListeners();

    if (removeFileOnDisk) {
      _deleteDirectories(shouldRemovedDirs);
    }
  }

  /// Deletes the directories in a separate isolate to avoid blocking the UI thread.
  static void _deleteDirectories(List<Directory> directories) {
    Isolate.run(() async {
      await SAFTaskWorker().init();
      for (var dir in directories) {
        try {
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        } catch (e) {
          continue;
        }
      }
    });
  }

  static String getChapterDirectoryName(String name) {
    var builder = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      var char = name[i];
      if (char == '/' || char == '\\' || char == ':' || char == '*' ||
          char == '?'
          || char == '"' || char == '<' || char == '>' || char == '|') {
        builder.write('_');
      } else {
        builder.write(char);
      }
    }
    return builder.toString();
  }
}

enum LocalSortType {
  name("name"),
  timeAsc("time_asc"),
  timeDesc("time_desc");

  final String value;

  const LocalSortType(this.value);

  static LocalSortType fromString(String value) {
    for (var type in values) {
      if (type.value == value) {
        return type;
      }
    }
    return name;
  }
}
