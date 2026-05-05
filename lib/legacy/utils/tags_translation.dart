/*
数据来自于:
https://github.com/EhTagTranslation/Database/tree/master/database

繁体中文由 @NeKoOuO (https://github.com/NeKoOuO) 提供
*/
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/opencc.dart';
import 'package:venera/utils/remote_text_normalizer.dart';

const _latestTagsDatabaseUrl =
    "https://github.com/EhTagTranslation/Database/releases/latest/download/db.text.json";
const _tagsDatabaseVersion = 7;
const _tagsCachePrefix = "ehtag_translation";
const _ehTagProviderKey = 'ehentai';

enum _TagLocale { simplified, traditional }

typedef EhTagTranslationDownloader = Future<String> Function();

class _LatestTagPackage {
  const _LatestTagPackage({required this.source, required this.sourceKey});

  final Map<String, Map<String, String>> source;
  final String? sourceKey;
}

Map<String, Map<String, String>> _decodeTagData(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  return {
    for (final entry in decoded.entries)
      entry.key: Map<String, String>.from(entry.value as Map),
  };
}

Map<String, Map<String, String>> _decodeLatestTagData(String text) {
  final decoded = jsonDecode(text) as Map<String, dynamic>;
  final version = decoded["version"];
  if (version != _tagsDatabaseVersion) {
    throw FormatException("Unsupported tag database version: $version");
  }
  final result = <String, Map<String, String>>{};
  final data = decoded["data"];
  if (data is! List) {
    throw const FormatException("Tag database data must be a list");
  }
  for (final namespaceData in data) {
    if (namespaceData is! Map) {
      continue;
    }
    final namespace = namespaceData["namespace"];
    final tags = namespaceData["data"];
    if (namespace is! String || tags is! Map) {
      continue;
    }
    result[namespace] = {
      for (final entry in tags.entries)
        if (entry.key is String &&
            entry.value is Map &&
            (entry.value as Map)["name"] is String)
          entry.key as String: (entry.value as Map)["name"] as String,
    };
  }
  if (result.isEmpty) {
    throw const FormatException("Tag database is empty");
  }
  return result;
}

String? _latestTagSourceKey(String text) {
  final decoded = jsonDecode(text) as Map<String, dynamic>;
  final head = decoded["head"];
  if (head is! Map) {
    return null;
  }
  final sha = head["sha"];
  return sha is String && sha.isNotEmpty ? sha : null;
}

_LatestTagPackage _decodeLatestTagPackage(String text) {
  final source = _decodeLatestTagData(text);
  final sourceKey = _latestTagSourceKey(text);
  return _LatestTagPackage(source: source, sourceKey: sourceKey);
}

Map<String, Map<String, String>> _convertTagData(
  Map<String, Map<String, String>> source,
  _TagLocale locale,
) {
  if (locale == _TagLocale.simplified) {
    return source;
  }
  return {
    for (final namespace in source.entries)
      namespace.key: {
        for (final tag in namespace.value.entries)
          tag.key: _toTraditional(tag.value),
      },
  };
}

String _toTraditional(String value) {
  try {
    return OpenCC.simplifiedToTraditional(value);
  } catch (_) {
    return value;
  }
}

extension TagsTranslation on String {
  static final Map<String, Map<String, String>> _data = {};
  static String? _loadedKey;
  static EhTagTranslationDownloader _downloader = _defaultDownloadLatestTagData;

  static Future<void> readData({
    bool forceReload = false,
    UnifiedComicsStore? store,
    Locale? localeOverride,
  }) async {
    final locale = localeOverride ?? App.locale;
    final tagLocale = _tagLocaleFrom(locale);
    final cacheKey = _cacheKeyFrom(locale, tagLocale);
    if (!forceReload && _loadedKey == cacheKey && _data.isNotEmpty) {
      return;
    }

    final dbLoaded = await _loadDbTagData(
      cacheKey,
      store: store ?? _storeOrNull(),
    );
    if (dbLoaded != null) {
      _data
        ..clear()
        ..addAll(dbLoaded);
      _loadedKey = cacheKey;
      return;
    }

    final cached = await _loadCachedTagData(cacheKey);
    if (cached != null) {
      _data
        ..clear()
        ..addAll(cached);
      _loadedKey = cacheKey;
      return;
    }

    final parsed = await _loadBundledTagData(tagLocale);
    _data
      ..clear()
      ..addAll(parsed);
    _loadedKey = cacheKey;
  }

  static Future<bool> refreshEhTaxonomy({
    UnifiedComicsStore? store,
    EhTagTranslationDownloader? downloader,
  }) async {
    final targetStore = store ?? _storeOrNull();
    if (targetStore == null) {
      throw StateError('UnifiedComicsStore is not available');
    }
    final text = await (downloader ?? _downloader)();
    final latest = await Isolate.run(() => _decodeLatestTagPackage(text));
    final source = latest.source;
    final sourceKey = latest.sourceKey;
    final existing = await targetStore.loadEhTagTaxonomy(
      providerKey: _ehTagProviderKey,
      locale: 'zh_CN',
    );
    if (sourceKey != null &&
        existing.isNotEmpty &&
        existing.first.sourceSha == sourceKey) {
      return false;
    }

    final simplified = source;
    final traditional = _convertTagData(source, _TagLocale.traditional);
    final records = <EhTagTaxonomyRecord>[
      ..._buildTaxonomyRecords(
        locale: 'zh_CN',
        data: simplified,
        sourceSha: sourceKey,
      ),
      ..._buildTaxonomyRecords(
        locale: 'zh_TW',
        data: traditional,
        sourceSha: sourceKey,
      ),
    ];
    await targetStore.replaceEhTagTaxonomyRecords(_ehTagProviderKey, records);
    await readData(forceReload: true, store: targetStore);
    return true;
  }

  static _TagLocale _tagLocaleFrom(Locale locale) {
    if (locale.languageCode == 'zh' &&
        (locale.countryCode == 'TW' || locale.countryCode == 'HK')) {
      return _TagLocale.traditional;
    }
    return _TagLocale.simplified;
  }

  static String _cacheKeyFrom(Locale locale, _TagLocale tagLocale) {
    if (tagLocale == _TagLocale.traditional && locale.countryCode == 'HK') {
      return "zh_HK";
    }
    if (tagLocale == _TagLocale.traditional) {
      return "zh_TW";
    }
    return "zh_CN";
  }

  static File? _cacheFile(String cacheKey) {
    if (!App.isInitialized) {
      return null;
    }
    return File("${App.dataPath}/${_tagsCachePrefix}_$cacheKey.json");
  }

  static Future<Map<String, Map<String, String>>?> _loadDbTagData(
    String cacheKey, {
    UnifiedComicsStore? store,
  }) async {
    if (store == null) {
      return null;
    }
    try {
      final requestedLocale = _dbLocaleForCacheKey(cacheKey);
      var rows = await store.loadEhTagTaxonomy(
        providerKey: _ehTagProviderKey,
        locale: requestedLocale,
      );
      final usedZhCnFallback = rows.isEmpty && requestedLocale != 'zh_CN';
      if (usedZhCnFallback) {
        // Keep DB-backed reads deterministic when global locale was changed by
        // other flows/tests but only zh_CN records exist.
        rows = await store.loadEhTagTaxonomy(
          providerKey: _ehTagProviderKey,
          locale: 'zh_CN',
        );
      }
      if (rows.isEmpty) {
        return null;
      }
      final data = <String, Map<String, String>>{};
      for (final row in rows) {
        data.putIfAbsent(row.namespace, () => <String, String>{})[row.tagKey] =
            row.translatedLabel;
      }
      if (data.isEmpty) {
        return null;
      }
      if (usedZhCnFallback && (cacheKey == 'zh_HK' || cacheKey == 'zh_TW')) {
        final converted = _convertTagData(data, _TagLocale.traditional);
        try {
          final bundledTraditional = await _loadBundledTagData(
            _TagLocale.traditional,
          );
          for (final namespace in converted.entries) {
            final bundledNamespace = bundledTraditional[namespace.key];
            if (bundledNamespace == null) {
              continue;
            }
            for (final tag in namespace.value.keys.toList()) {
              final bundledTranslation = bundledNamespace[tag];
              if (bundledTranslation != null &&
                  bundledTranslation.trim().isNotEmpty) {
                namespace.value[tag] = bundledTranslation;
              }
            }
          }
        } catch (_) {
          // Keep OpenCC-converted fallback when bundled traditional assets are unavailable.
        }
        return converted;
      }
      return data;
    } catch (e) {
      AppDiagnostics.warn(
        'tags.translation',
        'tags.translation.db_load_failed',
        data: {'cacheKey': cacheKey, 'error': '$e'},
      );
      return null;
    }
  }

  static Future<Map<String, Map<String, String>>?> _loadCachedTagData(
    String cacheKey,
  ) async {
    final cacheFile = _cacheFile(cacheKey);
    if (cacheFile == null || !await cacheFile.exists()) {
      return null;
    }
    try {
      final bytes = await cacheFile.readAsBytes();
      return await Isolate.run(() => _decodeTagData(bytes));
    } catch (e) {
      AppDiagnostics.warn(
        'tags.translation',
        'tags.translation.cache_load_failed',
        data: {'cacheKey': cacheKey, 'error': '$e'},
      );
      return null;
    }
  }

  static Future<Map<String, Map<String, String>>> _loadBundledTagData(
    _TagLocale tagLocale,
  ) async {
    if (tagLocale == _TagLocale.traditional) {
      try {
        final traditional = await _loadBundledTagDataFile(
          "assets/tags/zh_TW.json",
          "assets/tags_tw.json",
        );
        return traditional;
      } catch (_) {
        final simplified = await _loadBundledTagDataFile(
          "assets/tags/zh_CN.json",
          "assets/tags.json",
        );
        return _convertTagData(simplified, tagLocale);
      }
    }
    return _loadBundledTagDataFile(
      "assets/tags/zh_CN.json",
      "assets/tags.json",
    );
  }

  static Future<Map<String, Map<String, String>>> _loadBundledTagDataFile(
    String fileName,
    String legacyFileName,
  ) async {
    ByteData data;
    try {
      data = await rootBundle.load(fileName);
    } catch (_) {
      // Backward compatibility for older assets layout.
      data = await rootBundle.load(legacyFileName);
    }
    final bytes = Uint8List.sublistView(
      data.buffer.asUint8List(),
      data.offsetInBytes,
      data.offsetInBytes + data.lengthInBytes,
    );
    return Isolate.run(() => _decodeTagData(bytes));
  }

  static UnifiedComicsStore? _storeOrNull() {
    if (!App.isInitialized) {
      return null;
    }
    try {
      return App.unifiedComicsStore;
    } catch (_) {
      return null;
    }
  }

  static String _dbLocaleForCacheKey(String cacheKey) {
    return cacheKey == 'zh_HK' ? 'zh_TW' : cacheKey;
  }

  static List<EhTagTaxonomyRecord> _buildTaxonomyRecords({
    required String locale,
    required Map<String, Map<String, String>> data,
    required String? sourceSha,
  }) {
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return [
      for (final namespaceEntry in data.entries)
        for (final tagEntry in namespaceEntry.value.entries)
          EhTagTaxonomyRecord(
            providerKey: _ehTagProviderKey,
            locale: locale,
            namespace: namespaceEntry.key,
            tagKey: tagEntry.key,
            translatedLabel: tagEntry.value,
            sourceSha: sourceSha,
            sourceVersion: _tagsDatabaseVersion,
            updatedAt: updatedAt,
          ),
    ];
  }

  static void setDownloaderForTest(EhTagTranslationDownloader downloader) {
    _downloader = downloader;
  }

  static void resetStateForTest() {
    _downloader = _defaultDownloadLatestTagData;
    _loadedKey = null;
    _data.clear();
  }

  static Future<String> _defaultDownloadLatestTagData() async {
    final uri = Uri.parse(_latestTagsDatabaseUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          "Unexpected status ${response.statusCode}",
          uri: uri,
        );
      }
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  static bool _haveNamespace(String key) {
    return _data.containsKey(key);
  }

  /// 对tag进行处理后进行翻译: 代表'或'的分割符'|', namespace.
  static String _translateTags(String tag) {
    if (tag.contains('|')) {
      var splits = tag.split('|');
      return enTagsTranslations[splits[0].trim()] ??
          enTagsTranslations[splits[1].trim()] ??
          tag;
    } else if (tag.contains(':')) {
      var splits = tag.split(':');
      if (_haveNamespace(splits[0])) {
        return translationTagWithNamespace(splits[1], splits[0]);
      } else {
        return tag;
      }
    } else {
      return enTagsTranslations[tag] ?? tag;
    }
  }

  /// translate tag's text to chinese
  String get translateTagsToCN => _translateTags(this);

  String get translateTagIfNeed {
    var locale = App.locale;
    if (locale.languageCode == "zh") {
      return translateTagsToCN;
    } else {
      return this;
    }
  }

  static String translateTag(String tag) {
    if (tag.contains(':') && tag.indexOf(':') == tag.lastIndexOf(':')) {
      var [namespace, text] = tag.split(':');
      return translationTagWithNamespace(text, namespace);
    } else {
      return tag.translateTagsToCN;
    }
  }

  static String translationTagWithNamespace(String text, String namespace) {
    final original = text.toLowerCase();
    final normalized = namespace != "reclass" && original.endsWith('s')
        ? original.replaceLast('s', '')
        : original;
    String pick(Map<String, String> map) =>
        map[original] ?? map[normalized] ?? original;
    final translated = switch (namespace) {
      "male" => pick(maleTags),
      "female" => pick(femaleTags),
      "mixed" => pick(mixedTags),
      "other" => pick(otherTags),
      "parody" => pick(parodyTags),
      "character" => pick(characterTranslations),
      "group" => pick(groupTags),
      "cosplayer" => pick(cosplayerTags),
      "reclass" => pick(reclassTags),
      "language" => pick(languageTranslations),
      "artist" => pick(artistTags),
      _ => original.translateTagsToCN,
    };
    return RemoteTextNormalizer.normalizeLabel(
      translated,
      surface: RemoteTextSurface.tagLabel,
      locale: App.locale,
    );
  }

  String _categoryTextDynamic(String c) {
    if (App.locale.languageCode == "zh") {
      return translateTagsCategoryToCN;
    } else {
      return this;
    }
  }

  String get categoryTextDynamic => _categoryTextDynamic(this);

  String get translateTagsCategoryToCN => RemoteTextNormalizer.normalizeLabel(
    tagsCategoryTranslations[this] ?? this,
    surface: RemoteTextSurface.categoryLabel,
    locale: App.locale,
  );

  get tagsCategoryTranslations => switch (App.locale.countryCode) {
    "CN" => tagsCategoryTranslationsCN,
    "TW" => tagsCategoryTranslationsTW,
    "HK" => tagsCategoryTranslationsTW,
    _ => tagsCategoryTranslationsCN,
  };

  static const tagsCategoryTranslationsCN = {
    "language": "语言",
    "artist": "画师",
    "male": "男性",
    "female": "女性",
    "mixed": "混合",
    "other": "其它",
    "parody": "原作",
    "character": "角色",
    "group": "团队",
    "cosplayer": "Coser",
    "reclass": "重新分类",
    "Languages": "语言",
    "Artists": "画师",
    "Characters": "角色",
    "Groups": "团队",
    "Tags": "标签",
    "Parodies": "原作",
    "Categories": "分类",
    "Time": "时间",
  };

  static const tagsCategoryTranslationsTW = {
    "language": "語言",
    "artist": "畫師",
    "male": "男性",
    "female": "女性",
    "mixed": "混合",
    "other": "其他",
    "parody": "原作",
    "character": "角色",
    "group": "團隊",
    "cosplayer": "Coser",
    "reclass": "重新分類",
    "Languages": "語言",
    "Artists": "畫師",
    "Characters": "角色",
    "Groups": "團隊",
    "Tags": "標籤",
    "Parodies": "原作",
    "Categories": "分類",
    "Time": "時間",
  };

  static Map<String, String> get maleTags => _data["male"] ?? const {};

  static Map<String, String> get femaleTags => _data["female"] ?? const {};

  static Map<String, String> get languageTranslations =>
      _data["language"] ?? const {};

  static Map<String, String> get parodyTags => _data["parody"] ?? const {};

  static Map<String, String> get characterTranslations =>
      _data["character"] ?? const {};

  static Map<String, String> get otherTags => _data["other"] ?? const {};

  static Map<String, String> get mixedTags => _data["mixed"] ?? const {};

  static Map<String, String> get characterTags =>
      _data["character"] ?? const {};

  static Map<String, String> get artistTags => _data["artist"] ?? const {};

  static Map<String, String> get groupTags => _data["group"] ?? const {};

  static Map<String, String> get cosplayerTags =>
      _data["cosplayer"] ?? const {};

  static Map<String, String> get reclassTags => _data["reclass"] ?? const {};

  /// English to chinese translations
  ///
  /// Not include artists and group
  static MultipleMap<String, String> get enTagsTranslations => MultipleMap([
    maleTags,
    femaleTags,
    languageTranslations,
    parodyTags,
    characterTranslations,
    otherTags,
    mixedTags,
  ]);
}

enum TranslationType {
  female,
  male,
  mixed,
  language,
  other,
  group,
  artist,
  cosplayer,
  parody,
  character,
  reclass,
}

class MultipleMap<S, T> {
  final List<Map<S, T>> maps;

  MultipleMap(this.maps);

  T? operator [](S key) {
    for (var map in maps) {
      var value = map[key];
      if (value != null) {
        return value;
      }
    }
    return null;
  }
}
