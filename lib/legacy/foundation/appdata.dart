import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/database/app_db_helper.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/utils/data_sync.dart';
import 'package:venera/utils/init.dart';
import 'package:venera/utils/io.dart';

class Appdata with Init {
  Appdata._create([this._settingsStoreOverride]);
  static int _pendingWrites = 0;

  static int get pendingWrites => _pendingWrites;

  final Settings settings = Settings._create();

  var searchHistory = <String>[];

  bool _isSavingData = false;

  static const String _appdataBackupSuffix = '.m25_2_backup';

  final UnifiedComicsStore? _settingsStoreOverride;

  @visibleForTesting
  static Appdata createForTest({UnifiedComicsStore? settingsStore}) {
    return Appdata._create(settingsStore);
  }

  UnifiedComicsStore? get _settingsStore =>
      _settingsStoreOverride ?? App.unifiedComicsStoreOrNull;

  Future<void> saveData([bool sync = true]) async {
    while (_isSavingData) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    _isSavingData = true;
    _pendingWrites++;
    try {
      var futures = <Future>[];
      var json = toJson();
      var data = jsonEncode(json);
      var file = File(FilePath.join(App.dataPath, 'appdata.json'));
      futures.add(file.writeAsString(data));
      futures.add(_saveToDb());

      var disableSyncFields = json["settings"]["disableSyncFields"] as String;
      if (disableSyncFields.isNotEmpty) {
        var json4sync = jsonDecode(data);
        List<String> customDisableSync = splitField(disableSyncFields);
        for (var field in customDisableSync) {
          json4sync["settings"].remove(field);
        }
        var data4sync = jsonEncode(json4sync);
        var file4sync = File(FilePath.join(App.dataPath, 'syncdata.json'));
        futures.add(file4sync.writeAsString(data4sync));
      }

      await Future.wait(futures);
    } finally {
      _isSavingData = false;
      _pendingWrites--;
    }
    if (sync) {
      DataSync().uploadData();
    }
  }

  void addSearchHistory(String keyword) {
    if (searchHistory.contains(keyword)) {
      searchHistory.remove(keyword);
    }
    searchHistory.insert(0, keyword);
    if (searchHistory.length > 50) {
      searchHistory.removeLast();
    }
    saveData();
  }

  void removeSearchHistory(String keyword) {
    searchHistory.remove(keyword);
    saveData();
  }

  void clearSearchHistory() {
    searchHistory.clear();
    saveData();
  }

  Map<String, dynamic> toJson() {
    return {'settings': settings._data, 'searchHistory': searchHistory};
  }

  List<String> splitField(String merged) {
    return merged
        .split(',')
        .map((field) => field.trim())
        .where((field) => field.isNotEmpty)
        .toList();
  }

  /// Following fields are related to device-specific data and should not be synced.
  static const _disableSync = [
    "proxy",
    "authorizationRequired",
    "customImageProcessing",
    "webdav",
    "disableSyncFields",
    "deviceId",
  ];

  /// Sync data from another device
  void syncData(Map<String, dynamic> data) {
    if (data['settings'] is Map) {
      var settings = data['settings'] as Map<String, dynamic>;

      List<String> customDisableSync = splitField(
        this.settings["disableSyncFields"] as String,
      );

      for (var key in settings.keys) {
        if (!_disableSync.contains(key) && !customDisableSync.contains(key)) {
          this.settings[key] = settings[key];
        }
      }
    }
    searchHistory = List.from(data['searchHistory'] ?? []);
    saveData();
  }

  var implicitData = <String, dynamic>{};

  void writeImplicitData() async {
    while (_isSavingData) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    _isSavingData = true;
    _pendingWrites++;
    try {
      var file = File(FilePath.join(App.dataPath, 'implicitData.json'));
      await Future.wait([
        file.writeAsString(jsonEncode(implicitData)),
        _saveToDb(),
      ]);
    } finally {
      _isSavingData = false;
      _pendingWrites--;
    }
  }

  @override
  Future<void> doInit() async {
    var dataPath = (await getApplicationSupportDirectory()).path;
    var file = File(FilePath.join(dataPath, 'appdata.json'));
    var loadedFromDb = false;
    try {
      loadedFromDb = await _loadFromDb();
    } catch (e) {
      AppDiagnostics.warn(
        'appdata.runtime',
        'db_load_failed_fallback_json',
        data: {'error': '$e'},
      );
      loadedFromDb = false;
    }

    if (!loadedFromDb) {
      final migrated = await _loadFromLegacyJson(
        appDataFile: file,
        implicitDataFile: File(FilePath.join(dataPath, 'implicitData.json')),
      );
      if (migrated) {
        await _saveToDb();
      }
    }

    if ((settings["deviceId"] as String).isEmpty) {
      settings._data["deviceId"] = const Uuid().v4();
      await saveData(false);
    }
  }

  Future<bool> _loadFromLegacyJson({
    required File appDataFile,
    required File implicitDataFile,
  }) async {
    var loadedAny = false;
    if (await appDataFile.exists()) {
      try {
        var json = jsonDecode(await appDataFile.readAsString());
        for (var key in (json['settings'] as Map<String, dynamic>).keys) {
          if (json['settings'][key] != null) {
            settings[key] = json['settings'][key];
          }
        }
        searchHistory = List.from(json['searchHistory'] ?? const <String>[]);
        loadedAny = true;
        await _writeLegacyBackup(appDataFile);
      } catch (e) {
        AppDiagnostics.error(
          'appdata.runtime',
          e,
          message: 'load_appdata_json_failed',
        );
      }
    }
    if (await implicitDataFile.exists()) {
      try {
        implicitData = jsonDecode(await implicitDataFile.readAsString());
        loadedAny = true;
      } catch (e) {
        AppDiagnostics.error(
          'appdata.runtime',
          e,
          message: 'load_implicit_data_json_failed',
        );
      }
    }
    return loadedAny;
  }

  Future<void> _writeLegacyBackup(File appDataFile) async {
    final backupPath = '${appDataFile.path}$_appdataBackupSuffix';
    final backup = File(backupPath);
    if (await backup.exists()) {
      return;
    }
    if (await appDataFile.exists()) {
      await appDataFile.copy(backupPath);
    }
  }

  Future<bool> _loadFromDb() async {
    final store = _settingsStore;
    if (store == null) {
      return false;
    }
    final settingRows = await store.loadAppSettings();
    final searchRows = await store.loadSearchHistory();
    final implicitRows = await store.loadImplicitData();
    if (settingRows.isEmpty && searchRows.isEmpty && implicitRows.isEmpty) {
      return false;
    }

    for (final row in settingRows) {
      try {
        final decoded = _decodeSettingValue(row);
        if (!_isCompatibleWithDefaultShape(row.key, decoded)) {
          AppDiagnostics.warn(
            'appdata.runtime',
            'skip_db_setting_incompatible_shape',
            data: {'key': row.key, 'valueType': row.valueType},
          );
          continue;
        }
        settings[row.key] = decoded;
      } catch (e) {
        AppDiagnostics.warn(
          'appdata.runtime',
          'skip_invalid_db_setting',
          data: {'key': row.key, 'valueType': row.valueType, 'error': '$e'},
        );
      }
    }
    searchHistory = searchRows
        .map((row) => row.keyword)
        .toList(growable: false);
    implicitData = {
      for (final row in implicitRows) row.key: jsonDecode(row.valueJson),
    };
    return true;
  }

  Future<void> _saveToDb() async {
    final store = _settingsStore;
    if (store == null) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await AppDbHelper.instance.transaction('appdata.save', store, () async {
      final existingRows = await store.customSelect(
        'SELECT key FROM app_settings ORDER BY key ASC;',
      ).get();
      final existingKeys = existingRows
          .map((row) => row.read<String>('key'))
          .toSet();
      final currentKeys = settings._data.keys.toSet();
      final removedKeys = existingKeys.difference(currentKeys);

      for (final key in removedKeys) {
        await store.customStatement('DELETE FROM app_settings WHERE key = ?;', [
          key,
        ]);
      }

      for (final entry in settings._data.entries) {
        final value = entry.value;
        final valueType = _valueTypeOf(value);
        final syncPolicy = _disableSync.contains(entry.key)
            ? 'local_only'
            : 'syncable';
        await store.customStatement(
          '''
          INSERT INTO app_settings (key, value_json, value_type, sync_policy, updated_at_ms)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            value_type = excluded.value_type,
            sync_policy = excluded.sync_policy,
            updated_at_ms = excluded.updated_at_ms;
          ''',
          [
            entry.key,
            jsonEncode(value),
            valueType,
            syncPolicy,
            now,
          ],
        );
      }

      await store.customStatement('DELETE FROM search_history;');
      for (var i = 0; i < searchHistory.length; i++) {
        await store.customStatement(
          '''
          INSERT INTO search_history (keyword, position, updated_at_ms)
          VALUES (?, ?, ?)
          ON CONFLICT(keyword) DO UPDATE SET
            position = excluded.position,
            updated_at_ms = excluded.updated_at_ms;
          ''',
          [searchHistory[i], i, now],
        );
      }

      await store.customStatement('DELETE FROM implicit_data;');
      for (final entry in implicitData.entries) {
        await store.customStatement(
          '''
          INSERT INTO implicit_data (key, value_json, updated_at_ms)
          VALUES (?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at_ms = excluded.updated_at_ms;
          ''',
          [entry.key, jsonEncode(entry.value), now],
        );
      }
    });
  }

  String _valueTypeOf(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is bool) {
      return 'bool';
    }
    if (value is num) {
      return 'num';
    }
    if (value is String) {
      return 'string';
    }
    if (value is List) {
      return 'list';
    }
    if (value is Map) {
      return 'map';
    }
    return 'json';
  }

  dynamic _decodeSettingValue(AppSettingRecord row) {
    final decoded = jsonDecode(row.valueJson);
    switch (row.valueType) {
      case 'null':
        return null;
      case 'bool':
        if (decoded is bool) {
          return decoded;
        }
        throw StateError('expected bool');
      case 'string':
        if (decoded is String) {
          return decoded;
        }
        throw StateError('expected string');
      case 'int':
        if (decoded is int) {
          return decoded;
        }
        throw StateError('expected int');
      case 'double':
        if (decoded is double) {
          return decoded;
        }
        throw StateError('expected double');
      case 'num':
        if (decoded is num) {
          return decoded;
        }
        throw StateError('expected num');
      case 'list':
        if (decoded is List) {
          return List<dynamic>.from(decoded);
        }
        throw StateError('expected list');
      case 'map':
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        throw StateError('expected map');
      default:
        return decoded;
    }
  }

  bool _isCompatibleWithDefaultShape(String key, dynamic value) {
    if (!settings._data.containsKey(key)) {
      return true;
    }
    final defaultValue = settings._data[key];
    if (defaultValue == null || value == null) {
      return true;
    }
    if (defaultValue is Map) {
      return value is Map;
    }
    if (defaultValue is List) {
      return value is List;
    }
    if (defaultValue is bool) {
      return value is bool;
    }
    if (defaultValue is num) {
      return value is num;
    }
    if (defaultValue is String) {
      return value is String;
    }
    return true;
  }
}

final appdata = Appdata._create();

class Settings with ChangeNotifier {
  Settings._create();

  final _data = <String, dynamic>{
    'comicDisplayMode': 'detailed', // detailed, brief
    'comicTileScale': 1.00, // 0.75-1.25
    'color': 'system', // red, pink, purple, green, orange, blue
    'theme_mode': 'system', // light, dark, system
    'newFavoriteAddTo': 'end', // start, end
    'moveFavoriteAfterRead': 'none', // none, end, start
    'proxy': 'system', // direct, system, proxy string
    'explore_pages': [],
    'categories': [],
    'favorites': [],
    'searchSources': null,
    'showFavoriteStatusOnTile': true,
    'showHistoryStatusOnTile': false,
    'blockedWords': [],
    'blockedCommentWords': [],
    'defaultSearchTarget': null,
    'autoPageTurningInterval': 5, // in seconds
    'readerMode': 'galleryLeftToRight', // values of [ReaderMode]
    'readerScreenPicNumberForLandscape': 1, // 1 - 5
    'readerScreenPicNumberForPortrait': 1, // 1 - 5
    'enableTapToTurnPages': true,
    'reverseTapToTurnPages': false,
    'enablePageAnimation': true,
    'language': 'system', // system, zh-CN, zh-TW, en-US
    'enableRemoteChineseTextConversion': true,
    'cacheSize': 2048, // in MB
    'downloadThreads': 5,
    'enableLongPressToZoom': true,
    'longPressZoomPosition': "press", // press, center
    'checkUpdateOnStart': false,
    'limitImageWidth': true,
    'webdav': [], // empty means not configured
    "disableSyncFields": "", // "field1, field2, ..."
    'dataVersion': 0,
    'quickFavorite': null,
    'enableTurnPageByVolumeKey': true,
    'enableClockAndBatteryInfoInReader': true,
    'quickCollectImage': 'No', // No, DoubleTap, Swipe
    'authorizationRequired': false,
    'onClickFavorite': 'viewDetail', // viewDetail, read
    'enableDnsOverrides': false,
    'dnsOverrides': {},
    'enableCustomImageProcessing': false,
    'customImageProcessing': defaultCustomImageProcessing,
    'sni': true,
    'autoAddLanguageFilter': 'none', // none, chinese, english, japanese
    'comicSourceListUrl': _defaultSourceListUrl,
    'preloadImageCount': 4,
    'followUpdatesFolder': null,
    'initialPage': '0',
    'comicListDisplayMode': 'paging', // paging, continuous
    'showPageNumberInReader': true,
    'showSingleImageOnFirstPage': false,
    'enableDoubleTapToZoom': true,
    'reverseChapterOrder': false,
    'showSystemStatusBar': false,
    'comicSpecificSettings': <String, Map<String, dynamic>>{},
    'deviceSpecificSettings': <String, Map<String, dynamic>>{},
    'deviceId': '',
    'ignoreBadCertificate': false,
    'readerScrollSpeed': 1.0, // 0.5 - 3.0
    'localFavoritesFirst': true,
    'autoCloseFavoritePanel': false,
    'showChapterComments': true, // show chapter comments in reader
    'showChapterCommentsAtEnd':
        false, // show chapter comments at end of chapter
    'reader_use_source_ref_resolver': false,
    'enableDebugDiagnostics': false,
    'reader_next_enabled': true,
    'reader_next_history_enabled': true,
    'reader_next_favorites_enabled': true,
    'reader_next_downloads_enabled': true,
  };

  operator [](String key) {
    return _data[key];
  }

  operator []=(String key, dynamic value) {
    _data[key] = value;
    if (key != "dataVersion") {
      notifyListeners();
    }
  }

  void setEnabledComicSpecificSettings(
    String comicId,
    String sourceKey,
    bool enabled,
  ) {
    setReaderSetting(comicId, sourceKey, "enabled", enabled);
  }

  bool isComicSpecificSettingsEnabled(String? comicId, String? sourceKey) {
    if (comicId == null || sourceKey == null) {
      return false;
    }
    return _data['comicSpecificSettings']["$comicId@$sourceKey"]?["enabled"] ==
        true;
  }

  dynamic getReaderSetting(String comicId, String sourceKey, String key) {
    if (isComicSpecificSettingsEnabled(comicId, sourceKey)) {
      var comicValue =
          _data['comicSpecificSettings']["$comicId@$sourceKey"]?[key];
      if (comicValue != null) {
        return comicValue;
      }
    }
    return getDeviceReaderSetting(key);
  }

  void setReaderSetting(
    String comicId,
    String sourceKey,
    String key,
    dynamic value,
  ) {
    (_data['comicSpecificSettings'] as Map<String, dynamic>).putIfAbsent(
      "$comicId@$sourceKey",
      () => <String, dynamic>{},
    )[key] = value;
    notifyListeners();
  }

  void resetComicReaderSettings(String key) {
    (_data['comicSpecificSettings'] as Map).remove(key);
    notifyListeners();
  }

  void setEnabledDeviceSpecificSettings(bool enabled) {
    setDeviceReaderSetting("enabled", enabled);
  }

  bool isDeviceSpecificSettingsEnabled() {
    var deviceId = _data['deviceId'] as String;
    if (deviceId.isEmpty) {
      return false;
    }
    return _data['deviceSpecificSettings'][deviceId]?["enabled"] == true;
  }

  dynamic getDeviceReaderSetting(String key) {
    if (!isDeviceSpecificSettingsEnabled()) {
      return _data[key];
    }
    var deviceId = _data['deviceId'] as String;
    return _data['deviceSpecificSettings'][deviceId]?[key] ?? _data[key];
  }

  void setDeviceReaderSetting(String key, dynamic value) {
    var deviceId = _getOrCreateDeviceId();
    (_data['deviceSpecificSettings'] as Map<String, dynamic>).putIfAbsent(
      deviceId,
      () => <String, dynamic>{},
    )[key] = value;
    notifyListeners();
  }

  void resetDeviceReaderSettings() {
    var deviceId = _data['deviceId'] as String;
    if (deviceId.isEmpty) {
      return;
    }
    (_data['deviceSpecificSettings'] as Map).remove(deviceId);
    notifyListeners();
  }

  String _getOrCreateDeviceId() {
    var deviceId = _data['deviceId'] as String;
    if (deviceId.isNotEmpty) {
      return deviceId;
    }
    var id = const Uuid().v4();
    _data['deviceId'] = id;
    return id;
  }

  @override
  String toString() {
    return _data.toString();
  }
}

const defaultCustomImageProcessing = '''
/**
 * Process an image
 * @param image {ArrayBuffer} - The image to process
 * @param cid {string} - The comic ID
 * @param eid {string} - The episode ID
 * @param page {number} - The page number
 * @param sourceKey {string} - The source key
 * @returns {Promise<ArrayBuffer> | {image: Promise<ArrayBuffer>, onCancel: () => void}} - The processed image
 */
async function processImage(image, cid, eid, page, sourceKey) {
    let futureImage = new Promise((resolve, reject) => {
        resolve(image);
    });
    return futureImage;
}
''';

const _defaultSourceListUrl =
    "https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json";
