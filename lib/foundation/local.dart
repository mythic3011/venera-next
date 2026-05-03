import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/widgets.dart' show ChangeNotifier;
import 'package:flutter_saf/flutter_saf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/appdata_authority_audit.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/local_metadata/local_metadata.dart';
import 'package:venera/foundation/reader/reader_open_target.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/network/download.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/features/reader/presentation/reader_route_dispatch_authority.dart';
import 'package:venera/utils/import_sort.dart';
import 'package:venera/utils/io.dart';

import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'history.dart';

part 'local/local_comic.dart';
part 'local/local_sort_type.dart';

String? readLocalDirectoryBookmark() {
  recordAppdataAuthorityDiagnostic(
    channel: 'appdata.audit',
    event: 'appdata.authority.access',
    key: 'localDirectoryBookmark',
    storage: AppdataAuditStorage.implicitData,
    access: 'read',
    data: const <String, Object?>{'owner': 'LocalManager'},
  );
  final bookmark = appdata.implicitData['localDirectoryBookmark'];
  if (bookmark is String && bookmark.isNotEmpty) {
    return bookmark;
  }
  return null;
}

class LocalManager with ChangeNotifier {
  static const _localPathFilename = 'local_path';
  static const _iosLocalDirectoryBookmarkKey = 'localDirectoryBookmark';
  static const _localComicsTable = 'legacy_local_comics';
  static LocalManager? _instance;

  LocalManager._();

  factory LocalManager() {
    return _instance ??= LocalManager._();
  }

  late Database _db;
  late LocalMetadataRepository _metadataRepository;
  bool _isInitialized = false;
  Future<void>? _initializingFuture;

  bool get isInitialized => _isInitialized;

  /// path to the directory where all the comics are stored
  late String path;

  Never _throwLegacyUnavailable(String operation) {
    throw StateError(
      'Legacy local manager unavailable for $operation. '
      'This access is legacy-only; canonical import/sync must not depend on LocalManager.',
    );
  }

  String requireLegacyPathForModelAccess({required String operation}) {
    if (!_isInitialized) {
      _throwLegacyUnavailable(operation);
    }
    if (!_hasResolvedPath()) {
      _throwLegacyUnavailable(operation);
    }
    return path;
  }

  Directory get directory => Directory(path);

  void _checkNoMedia() {
    if (App.isAndroid) {
      var file = File(FilePath.join(path, '.nomedia'));
      if (!file.existsSync()) {
        file.createSync();
      }
    }
  }

  String get _localPathFilePath =>
      FilePath.join(App.dataPath, _localPathFilename);

  String? get _iosLocalDirectoryBookmark => readLocalDirectoryBookmark();

  // return error message if failed
  Future<String?> setNewPath(String newPath, {String? iosBookmark}) async {
    if (App.isIOS && (iosBookmark == null || iosBookmark.isEmpty)) {
      return "Missing directory bookmark";
    }
    var newDir = Directory(newPath);
    if (!await newDir.exists()) {
      return "Directory does not exist";
    }
    if (!await newDir.list().isEmpty) {
      return "Directory is not empty";
    }
    try {
      await copyDirectoryIsolate(directory, newDir);
      await File(_localPathFilePath).writeAsString(newPath);
      if (App.isIOS) {
        appdata.implicitData[_iosLocalDirectoryBookmarkKey] = iosBookmark;
        appdata.writeImplicitData();
      }
    } catch (e, s) {
      AppDiagnostics.error('io.runtime', e, stackTrace: s);
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
      AppDiagnostics.error(
        'io.runtime',
        e,
        message: 'create_test_file_failed_fallback_default_path',
      );
      path = await findDefaultPath();
    }
  }

  Future<void> init({bool skipSourceInit = false}) async {
    if (_isInitialized) {
      return;
    }
    final inFlight = _initializingFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _doInit(skipSourceInit: skipSourceInit);
    _initializingFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializingFuture, future)) {
        _initializingFuture = null;
      }
    }
  }

  Future<void> ensureInitialized({bool skipSourceInit = false}) {
    return init(skipSourceInit: skipSourceInit);
  }

  Future<void> _doInit({bool skipSourceInit = false}) async {
    final canonicalDbPath = canonicalDomainDatabasePath(App.dataPath);
    Directory(File(canonicalDbPath).parent.path).createSync(recursive: true);
    _db = sqlite3.open(canonicalDbPath);
    AppDiagnostics.info(
      'storage.route',
      'Local library routed to canonical DB file',
      data: {
        'domain': 'local_library',
        'route': 'canonical',
        'legacyDbFile': 'local.db',
        'canonicalDbFile': canonicalDomainDatabaseFileName,
      },
    );
    _db.execute('''
      CREATE TABLE IF NOT EXISTS $_localComicsTable (
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
    if (App.isIOS) {
      final restoredPath = await _restoreIosExternalPath();
      if (restoredPath != null) {
        path = restoredPath;
      }
    }
    if (!_hasResolvedPath() && File(_localPathFilePath).existsSync()) {
      path = File(_localPathFilePath).readAsStringSync();
      if (!directory.existsSync()) {
        path = await findDefaultPath();
      }
    } else if (!_hasResolvedPath()) {
      path = await findDefaultPath();
    }
    try {
      if (!directory.existsSync()) {
        await directory.create();
      }
    } catch (e, s) {
      AppDiagnostics.error('io.runtime', e, stackTrace: s, message: 'create_local_folder_failed');
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
    _isInitialized = true;
  }

  bool _hasResolvedPath() {
    try {
      return path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _restoreIosExternalPath() async {
    final bookmark = _iosLocalDirectoryBookmark;
    if (bookmark == null) {
      return null;
    }
    AppDiagnostics.warn(
      'io.runtime',
      "iOS local directory bookmark restore is unavailable; falling back to default path.",
    );
    return null;
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
    final existing =
        _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(
          seriesKey: seriesKey,
          groups: const [],
          chapters: const {},
        );
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
    final existing =
        _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(
          seriesKey: seriesKey,
          groups: const [],
          chapters: const {},
        );
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

  Future<void> reorderGroups(
    LocalComic comic,
    List<String> orderedGroupIds,
  ) async {
    final seriesKey = _metadataSeriesKey(comic);
    final existing =
        _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(
          seriesKey: seriesKey,
          groups: const [],
          chapters: const {},
        );
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
    await _metadataRepository.upsertSeries(
      existing.copyWith(groups: reordered),
    );
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
    final existing =
        _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(
          seriesKey: seriesKey,
          groups: const [],
          chapters: const {},
        );
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
    await _metadataRepository.upsertSeries(
      existing.copyWith(chapters: chapters),
    );
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
    final existing =
        _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(
          seriesKey: seriesKey,
          groups: const [],
          chapters: const {},
        );
    final chapters = Map<String, LocalChapterMeta>.from(existing.chapters);
    final current = chapters[chapterId];
    chapters[chapterId] = LocalChapterMeta(
      chapterId: chapterId,
      displayTitle: normalizedTitle,
      groupId: current?.groupId,
      sortOrder: current?.sortOrder,
    );
    await _metadataRepository.upsertSeries(
      existing.copyWith(chapters: chapters),
    );
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
    final existing =
        _metadataRepository.getSeries(seriesKey) ??
        LocalSeriesMeta(
          seriesKey: seriesKey,
          groups: const [],
          chapters: const {},
        );
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
    await _metadataRepository.upsertSeries(
      existing.copyWith(chapters: chapters),
    );
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
      chaptersByGroup[targetGroupId]!.add((
        chapterId,
        effectiveTitle,
        sortOrder,
      ));
    }

    final availableGroups =
        <LocalChapterGroup>[
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
      SELECT id FROM $_localComicsTable WHERE comic_type = ?
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
    var downloaded = List<String>.from(comic.downloadedChapters);
    if (old != null) {
      downloaded.addAll(old.downloadedChapters);
    }
    _db.execute(
      'INSERT OR REPLACE INTO $_localComicsTable VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
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
      'DELETE FROM $_localComicsTable WHERE id = ? AND comic_type = ?;',
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
      SELECT * FROM $_localComicsTable
      ORDER BY
        ${sortType.value == 'name' ? 'title' : 'created_at'}
        ${sortType.value == 'time_asc' ? 'ASC' : 'DESC'}
      ;
    ''');
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  LocalComic? find(String id, ComicType comicType) {
    final res = _db.select(
      'SELECT * FROM $_localComicsTable WHERE id = ? AND comic_type = ?;',
      [id, comicType.value],
    );
    if (res.isEmpty) {
      return null;
    }
    return LocalComic.fromRow(res.first);
  }

  LocalComic? findBySourceKey(String id, String sourceKey) {
    return find(id, ComicType.fromKey(sourceKey));
  }

  @override
  void dispose() {
    super.dispose();
    _db.dispose();
    _isInitialized = false;
  }

  List<LocalComic> getRecent() {
    final res = _db.select('''
      SELECT * FROM $_localComicsTable
      ORDER BY created_at DESC
      LIMIT 20;
    ''');
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  int get count {
    final res = _db.select('''
      SELECT COUNT(*) FROM $_localComicsTable;
    ''');
    return res.first[0] as int;
  }

  LocalComic? findByName(String name) {
    final res = _db.select(
      '''
      SELECT * FROM $_localComicsTable
      WHERE title = ? OR directory = ?;
    ''',
      [name, name],
    );
    if (res.isEmpty) {
      return null;
    }
    return LocalComic.fromRow(res.first);
  }

  List<LocalComic> search(String keyword) {
    final res = _db.select(
      '''
      SELECT * FROM $_localComicsTable
      WHERE title LIKE ? OR tags LIKE ? OR subtitle LIKE ?
      ORDER BY created_at DESC;
    ''',
      ['%$keyword%', '%$keyword%', '%$keyword%'],
    );
    return res.map((row) => LocalComic.fromRow(row)).toList();
  }

  Future<List<String>> getImages(String id, ComicType type, Object ep) async {
    if (ep is! String && ep is! int) {
      throw "Invalid ep";
    }
    var comic = find(id, type) ?? (throw "Comic Not Found");
    var directory = Directory(comic.baseDir);
    if (comic.hasChapters) {
      var cid = ep is int
          ? comic.chapters!.ids.elementAt(ep - 1)
          : (ep as String);
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

  Future<List<String>> getImagesBySourceKey(
    String id,
    String sourceKey,
    Object ep,
  ) {
    return getImages(id, ComicType.fromKey(sourceKey), ep);
  }

  Future<void> reorderComicPages(
    LocalComic comic,
    Object ep,
    List<String> orderedFileNames,
  ) async {
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
        .where(
          (f) =>
              !f.name.startsWith('cover.') &&
              !f.name.startsWith('.') &&
              !isHiddenOrMacMetadataPath(f.name),
        )
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
      final original = File(
        FilePath.join(chapterDir.path, orderedFileNames[i]),
      );
      final tempName = "__reorder_tmp__$i.${original.extension}";
      final tempPath = FilePath.join(chapterDir.path, tempName);
      await original.rename(tempPath);
      tempFiles.add(tempPath);
    }
    for (var i = 0; i < tempFiles.length; i++) {
      final temp = File(tempFiles[i]);
      final targetPath = FilePath.join(
        chapterDir.path,
        "${i + 1}.${temp.extension}",
      );
      await temp.rename(targetPath);
    }
  }

  bool isDownloaded(
    String id,
    ComicType type, [
    int? ep,
    ComicChapters? chapters,
  ]) {
    var comic = find(id, type);
    if (comic == null) return false;
    if (comic.chapters == null || ep == null) return true;
    if (chapters != null) {
      if (comic.chapters?.length != chapters.length) {
        // update
        add(
          LocalComic(
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
          ),
        );
      }
    }
    return comic.downloadedChapters.contains(
      (chapters ?? comic.chapters)!.ids.elementAtOrNull(ep - 1),
    );
  }

  bool isDownloadedBySourceKey(
    String id,
    String sourceKey, [
    int? ep,
    ComicChapters? chapters,
  ]) {
    return isDownloaded(id, ComicType.fromKey(sourceKey), ep, chapters);
  }

  List<DownloadTask> downloadingTasks = [];

  bool isDownloading(String id, ComicType type) {
    return downloadingTasks.any(
      (element) => element.id == id && element.comicType == type,
    );
  }

  Future<Directory> findValidDirectory(
    String id,
    ComicType type,
    String name,
  ) async {
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
    await File(
      FilePath.join(App.dataPath, 'downloading_tasks.json'),
    ).writeAsString(jsonEncode(tasks));
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
        AppDiagnostics.error('local.manager', e, message: 'restore_downloading_tasks_failed');
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
        'UPDATE $_localComicsTable SET cover = ? WHERE id = ? AND comic_type = ?;',
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
        'UPDATE $_localComicsTable SET chapters = ?, downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
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
        'DELETE FROM $_localComicsTable WHERE id = ? AND comic_type = ?;',
        [c.id, c.comicType.value],
      );
      _metadataRepository.removeSeries(_metadataSeriesKey(c));
    }
    var shouldRemovedDirs = <Directory>[];
    for (var chapter in chapters) {
      var dir = Directory(
        FilePath.join(c.baseDir, getChapterDirectoryName(chapter)),
      );
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
      'UPDATE $_localComicsTable SET chapters = ? WHERE id = ? AND comic_type = ?;',
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
      'UPDATE $_localComicsTable SET chapters = ?, downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
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

      Future<void> appendOneChapter(
        Directory sourceDir,
        String sourceTitle,
      ) async {
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
      'UPDATE $_localComicsTable SET chapters = ?, downloadedChapters = ? WHERE id = ? AND comic_type = ?;',
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

  void batchDeleteComics(
    List<LocalComic> comics, [
    bool removeFileOnDisk = true,
    bool removeFavoriteAndHistory = true,
  ]) {
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
          'DELETE FROM $_localComicsTable WHERE id = ? AND comic_type = ?;',
          [c.id, c.comicType.value],
        );
      }
    } catch (e, s) {
      AppDiagnostics.error('local.manager', e, stackTrace: s, message: 'batch_delete_comics_failed');
      _db.execute('ROLLBACK;');
      return;
    }
    _db.execute('COMMIT;');

    var comicIDs = comics
        .map((e) => ComicID.fromSourceKey(e.comicType.sourceKey, e.id))
        .toList();

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
      if (char == '/' ||
          char == '\\' ||
          char == ':' ||
          char == '*' ||
          char == '?' ||
          char == '"' ||
          char == '<' ||
          char == '>' ||
          char == '|') {
        builder.write('_');
      } else {
        builder.write(char);
      }
    }
    return builder.toString();
  }
}
