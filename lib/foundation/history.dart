import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show ChangeNotifier;
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/history_store.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/image_provider/image_favorites_provider.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/foundation/reader/resume_target_store.dart';
import 'package:venera/utils/channel.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/translations.dart';

import 'app.dart';
import 'appdata.dart';
import 'consts.dart';

part "image_favorites.dart";

typedef HistoryType = ComicType;

abstract mixin class HistoryMixin {
  String get title;

  String? get subTitle;

  String get cover;

  String get id;

  int? get maxPage => null;

  HistoryType get historyType;
}

class History implements Comic {
  HistoryType type;

  DateTime time;

  @override
  String title;

  @override
  String subtitle;

  @override
  String cover;

  /// index of chapters. 1-based.
  int ep;

  /// index of pages. 1-based.
  int page;

  /// index of chapter groups. 1-based.
  /// If [group] is not null, [ep] is the index of chapter in the group.
  int? group;

  @override
  String id;

  /// readEpisode is a set of episode numbers that have been read.
  /// For normal chapters, it is a set of chapter numbers.
  /// For grouped chapters, it is a set of strings in the format of "group_number-chapter_number".
  /// 1-based.
  Set<String> readEpisode;

  @override
  int? maxPage;

  History.fromModel({
    required HistoryMixin model,
    required this.ep,
    required this.page,
    this.group,
    Set<String>? readChapters,
    DateTime? time,
  }) : type = model.historyType,
       title = model.title,
       subtitle = model.subTitle ?? '',
       cover = model.cover,
       id = model.id,
       readEpisode = readChapters ?? <String>{},
       time = time ?? DateTime.now();

  History.fromMap(Map<String, dynamic> map)
    : type = HistoryType(map["type"]),
      time = DateTime.fromMillisecondsSinceEpoch(map["time"]),
      title = map["title"],
      subtitle = map["subtitle"],
      cover = map["cover"],
      ep = map["ep"],
      page = map["page"],
      id = map["id"],
      readEpisode = Set<String>.from(
        (map["readEpisode"] as List<dynamic>?)?.toSet() ?? const <String>{},
      ),
      maxPage = map["max_page"];

  @override
  String toString() {
    return 'History{type: $type, time: $time, title: $title, subtitle: $subtitle, cover: $cover, ep: $ep, page: $page, id: $id}';
  }

  History.fromRecord(HistoryRecord row)
    : type = HistoryType(row.type),
      time = DateTime.fromMillisecondsSinceEpoch(row.timeMillis),
      title = row.title,
      subtitle = row.subtitle,
      cover = row.cover,
      ep = row.ep,
      page = row.page,
      id = row.id,
      readEpisode = Set<String>.from(
        (row.readEpisode).split(',').where((element) => element != ""),
      ),
      maxPage = row.maxPage,
      group = row.chapterGroup;

  @override
  bool operator ==(Object other) {
    return other is History && type == other.type && id == other.id;
  }

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String get description {
    var res = "";
    if (group != null) {
      res += "${"Group @group".tlParams({"group": group!})} - ";
    }
    if (ep >= 1) {
      res += "Chapter @ep".tlParams({"ep": ep});
    }
    if (page >= 1) {
      if (ep >= 1) {
        res += " - ";
      }
      res += "Page @page".tlParams({"page": page});
    }
    return res;
  }

  @override
  String? get favoriteId => null;

  @override
  String? get language => null;

  @override
  String get sourceKey => type == ComicType.local
      ? 'local'
      : type.comicSource?.key ?? "Unknown:${type.value}";

  @override
  double? get stars => null;

  @override
  List<String>? get tags => null;

  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError();
  }
}

class HistoryManager with ChangeNotifier {
  static HistoryManager? cache;

  HistoryManager.create();

  factory HistoryManager() =>
      cache == null ? (cache = HistoryManager.create()) : cache!;

  late HistoryStore _store;
  final Map<String, History> _historyMap = {};
  late final ResumeTargetStore _resumeStore = ResumeTargetStore(
    appdata.implicitData,
  );

  static const _snapshotFlag = 'reader_use_resume_source_ref_snapshot';

  int get length => _historyMap.length;

  /// Cache of history ids. Improve the performance of find operation.
  Map<String, bool>? _cachedHistoryIds;

  /// Cache records recently modified by the app. Improve the performance of listeners.
  final cachedHistories = <String, History>{};

  bool isInitialized = false;

  Future<void> init() async {
    if (isInitialized) {
      return;
    }
    _store = HistoryStore("${App.dataPath}/history.db");
    await _store.init();
    final rows = await _store.loadAllHistory();
    _historyMap.clear();
    for (final row in rows) {
      _historyMap[row.id] = History.fromRecord(row);
    }

    notifyListeners();
    ImageFavoriteManager().init();
    isInitialized = true;
  }

  bool _haveAsyncTask = false;

  /// Create a isolate to add history to prevent blocking the UI thread.
  Future<void> addHistoryAsync(History newItem) async {
    while (_haveAsyncTask) {
      await Future.delayed(Duration(milliseconds: 20));
    }

    _haveAsyncTask = true;
    await _store.upsertHistory(
      HistoryRecord(
        id: newItem.id,
        title: newItem.title,
        subtitle: newItem.subtitle,
        cover: newItem.cover,
        timeMillis: newItem.time.millisecondsSinceEpoch,
        type: newItem.type.value,
        ep: newItem.ep,
        page: newItem.page,
        readEpisode: newItem.readEpisode.join(','),
        maxPage: newItem.maxPage,
        chapterGroup: newItem.group,
      ),
    );
    _haveAsyncTask = false;
    if (_cachedHistoryIds == null) {
      updateCache();
    } else {
      _cachedHistoryIds![newItem.id] = true;
    }
    cachedHistories[newItem.id] = newItem;
    if (cachedHistories.length > 10) {
      cachedHistories.remove(cachedHistories.keys.first);
    }
    notifyListeners();
  }

  void updateResumeSnapshot({
    required String comicId,
    required ComicType type,
    required int chapter,
    required int? group,
    required int page,
    required SourceRef sourceRef,
  }) {
    if (!_isResumeSnapshotEnabled()) {
      return;
    }
    _resumeStore.write(
      comicId: comicId,
      type: type,
      chapter: chapter,
      group: group,
      page: page,
      sourceRef: sourceRef,
    );
    appdata.writeImplicitData();
  }

  SourceRef? findResumeSourceRef(String comicId, ComicType type) {
    if (!_isResumeSnapshotEnabled()) {
      return null;
    }
    final result = _resumeStore.readWithDiagnostic(comicId, type);
    if (result.diagnostic != null) {
      Log.info("History", _mapSnapshotDiagnostic(result.diagnostic!));
    }
    return result.snapshot?.sourceRef;
  }

  bool _isResumeSnapshotEnabled() {
    return appdata.settings['reader_use_source_ref_resolver'] == true &&
        appdata.settings[_snapshotFlag] == true;
  }

  String _mapSnapshotDiagnostic(ResumeSnapshotDiagnosticCode code) {
    return switch (code) {
      ResumeSnapshotDiagnosticCode.malformed => 'RESUME_SNAPSHOT_MALFORMED',
      ResumeSnapshotDiagnosticCode.unsupportedVersion =>
        'RESUME_SNAPSHOT_UNSUPPORTED_VERSION',
      ResumeSnapshotDiagnosticCode.missingRequiredField =>
        'RESUME_SNAPSHOT_MISSING_REQUIRED_FIELD',
      ResumeSnapshotDiagnosticCode.sourceRefInvalid =>
        'RESUME_SNAPSHOT_SOURCE_REF_INVALID',
    };
  }

  /// add history. if exists, update time.
  ///
  /// This function would be called when user start reading.
  Future<void> addHistory(History newItem) async {
    _historyMap[newItem.id] = newItem;
    await _store.upsertHistory(
      HistoryRecord(
        id: newItem.id,
        title: newItem.title,
        subtitle: newItem.subtitle,
        cover: newItem.cover,
        timeMillis: newItem.time.millisecondsSinceEpoch,
        type: newItem.type.value,
        ep: newItem.ep,
        page: newItem.page,
        readEpisode: newItem.readEpisode.join(','),
        maxPage: newItem.maxPage,
        chapterGroup: newItem.group,
      ),
    );
    if (_cachedHistoryIds == null) {
      updateCache();
    } else {
      _cachedHistoryIds![newItem.id] = true;
    }
    cachedHistories[newItem.id] = newItem;
    if (cachedHistories.length > 10) {
      cachedHistories.remove(cachedHistories.keys.first);
    }
    notifyListeners();
  }

  void addHistoryDeferred(History newItem) {
    unawaited(addHistory(newItem));
  }

  void clearHistory() {
    _historyMap.clear();
    unawaited(_store.clearHistory());
    updateCache();
    notifyListeners();
  }

  void clearUnfavoritedHistory() {
    final toDelete = <(String, int)>[];
    for (var element in _historyMap.values) {
      final id = element.id;
      final type = element.type;
      if (!LocalFavoritesManager().isExist(id, type)) {
        toDelete.add((id, type.value));
      }
    }
    for (final item in toDelete) {
      _historyMap.remove(item.$1);
    }
    unawaited(_store.batchDeleteHistories(toDelete));
    updateCache();
    notifyListeners();
  }

  void remove(String id, ComicType type) async {
    _historyMap.remove(id);
    unawaited(_store.deleteHistory(id, type.value));
    updateCache();
    notifyListeners();
  }

  void updateCache() {
    _cachedHistoryIds = {};
    for (var id in _historyMap.keys) {
      _cachedHistoryIds![id] = true;
    }
    for (var key in cachedHistories.keys.toList()) {
      if (!_cachedHistoryIds!.containsKey(key)) {
        cachedHistories.remove(key);
      }
    }
  }

  History? find(String id, ComicType type) {
    if (_cachedHistoryIds == null) {
      updateCache();
    }
    if (!_cachedHistoryIds!.containsKey(id)) {
      return null;
    }
    if (cachedHistories.containsKey(id)) {
      return cachedHistories[id];
    }

    final history = _historyMap[id];
    if (history == null || history.type != type) {
      return null;
    }
    return history;
  }

  List<History> getAll() {
    final list = _historyMap.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  /// 获取最近阅读的漫画
  List<History> getRecent() {
    return getAll().take(20).toList();
  }

  /// 获取历史记录的数量
  int count() {
    return _historyMap.length;
  }

  Future<void> close() async {
    isInitialized = false;
    await _store.close();
  }

  void batchDeleteHistories(List<ComicID> histories) {
    if (histories.isEmpty) return;
    final deleteItems = <(String, int)>[];
    for (var history in histories) {
      _historyMap.remove(history.id);
      deleteItems.add((history.id, history.type.value));
    }
    unawaited(_store.batchDeleteHistories(deleteItems));
    updateCache();
    notifyListeners();
  }

  /// Refresh history info from comic source.
  /// Fetches the latest cover, title and subtitle from the source.
  /// Keeps the reading progress (ep, page, etc.).
  Future<bool> refreshHistoryInfo(History history) async {
    if (history.sourceKey == 'local') {
      // Local comics don't need refresh
      return false;
    }

    return await _refreshSingleHistory(history);
  }

  /// Internal method to refresh a single history
  /// Retries up to 3 times on failure with 2 second delay between retries
  Future<bool> _refreshSingleHistory(History history) async {
    var comicSource = ComicSource.find(history.sourceKey);
    if (comicSource == null || comicSource.loadComicInfo == null) {
      return false;
    }

    int retries = 3;
    while (true) {
      try {
        var res = await comicSource.loadComicInfo!(history.id);
        if (res.error) {
          await Future.delayed(const Duration(seconds: 2));
          retries--;
          if (retries == 0) {
            return false;
          }
          continue;
        }

        var comicDetails = res.data;
        // Update history info while keeping reading progress
        var updatedHistory = History.fromMap({
          'type': history.type.value,
          'time': history.time.millisecondsSinceEpoch,
          'title': comicDetails.title,
          'subtitle': comicDetails.subTitle ?? '',
          'cover': comicDetails.cover,
          'ep': history.ep,
          'page': history.page,
          'id': history.id,
          'readEpisode': history.readEpisode.toList(),
          'max_page': history.maxPage,
        });
        updatedHistory.group = history.group;

        await addHistory(updatedHistory);
        return true;
      } catch (e, s) {
        Log.error("History", "Exception while refreshing history info: $e\n$s");
        await Future.delayed(const Duration(seconds: 2));
        retries--;
        if (retries == 0) {
          return false;
        }
      }
    }
  }

  /// Refresh all histories from comic sources.
  /// Returns a stream with progress updates.
  /// From e0ea449c.
  Stream<RefreshProgress> refreshAllHistoriesStream() {
    var controller = StreamController<RefreshProgress>();
    _refreshAllHistoriesBase(controller);
    return controller.stream;
  }

  void _refreshAllHistoriesBase(
    StreamController<RefreshProgress> controller,
  ) async {
    var histories = getAll();
    int total = histories.length;
    int current = 0;
    int success = 0;
    int failed = 0;
    int skipped = 0;

    controller.add(RefreshProgress(total, current, success, failed, skipped));

    var historiesToRefresh = <History>[];
    for (var history in histories) {
      if (history.sourceKey == 'local') {
        skipped++;
        current++;
        controller.add(
          RefreshProgress(total, current, success, failed, skipped),
        );
        continue;
      }
      historiesToRefresh.add(history);
    }

    total = historiesToRefresh.length;
    current = 0;
    controller.add(RefreshProgress(total, current, success, failed, skipped));

    var channel = Channel<History>(10);

    () async {
      var c = 0;
      for (var history in historiesToRefresh) {
        await channel.push(history);
        c++;
        if (c % 5 == 0) {
          var delay = c % 100 + 1;
          if (delay > 10) {
            delay = 10;
          }
          await Future.delayed(Duration(seconds: delay));
        }
      }
      channel.close();
    }();

    var updateFutures = <Future>[];
    for (var i = 0; i < 5; i++) {
      var f = () async {
        while (true) {
          var history = await channel.pop();
          if (history == null) {
            break;
          }
          var result = await _refreshSingleHistory(history);
          current++;
          if (result) {
            success++;
          } else {
            failed++;
          }
          controller.add(
            RefreshProgress(total, current, success, failed, skipped),
          );
        }
      }();
      updateFutures.add(f);
    }

    await Future.wait(updateFutures);

    notifyListeners();
    controller.close();
  }
}

class RefreshProgress {
  final int total;
  final int current;
  final int success;
  final int failed;
  final int skipped;

  RefreshProgress(
    this.total,
    this.current,
    this.success,
    this.failed,
    this.skipped,
  );
}
