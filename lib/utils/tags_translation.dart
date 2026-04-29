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
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/opencc.dart';

const _latestTagsDatabaseUrl =
    "https://github.com/EhTagTranslation/Database/releases/latest/download/db.text.json";
const _tagsDatabaseVersion = 7;
const _tagsCachePrefix = "ehtag_translation";

enum _TagLocale { simplified, traditional }

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
          tag.key: OpenCC.simplifiedToTraditional(tag.value),
      },
  };
}

extension TagsTranslation on String {
  static final Map<String, Map<String, String>> _data = {};
  static String? _loadedKey;

  static Future<void> readData() async {
    final locale = App.locale;
    final tagLocale = _tagLocaleFrom(locale);
    final cacheKey = _cacheKeyFrom(locale, tagLocale);
    if (_loadedKey == cacheKey && _data.isNotEmpty) {
      return;
    }

    final latest = await _downloadAndCacheLatestTagData(tagLocale, cacheKey);
    if (latest != null) {
      _data
        ..clear()
        ..addAll(latest);
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

  static File? _cacheMetaFile(String cacheKey) {
    if (!App.isInitialized) {
      return null;
    }
    return File("${App.dataPath}/${_tagsCachePrefix}_$cacheKey.meta.json");
  }

  static Future<Map<String, Map<String, String>>?>
  _downloadAndCacheLatestTagData(_TagLocale tagLocale, String cacheKey) async {
    try {
      final text = await _downloadLatestTagData();
      final sourceKey = await Isolate.run(() => _latestTagSourceKey(text));
      if (sourceKey != null && await _cacheSourceKey(cacheKey) == sourceKey) {
        final cached = await _loadCachedTagData(cacheKey);
        if (cached != null) {
          return cached;
        }
      }
      final source = await Isolate.run(() => _decodeLatestTagData(text));
      final translated = _convertTagData(source, tagLocale);
      final cacheFile = _cacheFile(cacheKey);
      if (cacheFile != null) {
        await cacheFile.writeAsString(jsonEncode(translated), flush: true);
      }
      await _writeCacheSourceKey(cacheKey, sourceKey);
      return translated;
    } catch (e) {
      Log.warning("Tags Translation", "Failed to update latest tag data: $e");
      return null;
    }
  }

  static Future<String?> _cacheSourceKey(String cacheKey) async {
    final metaFile = _cacheMetaFile(cacheKey);
    final cacheFile = _cacheFile(cacheKey);
    if (metaFile == null ||
        cacheFile == null ||
        !await metaFile.exists() ||
        !await cacheFile.exists()) {
      return null;
    }
    try {
      final decoded =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final sourceKey = decoded["sourceKey"];
      return sourceKey is String && sourceKey.isNotEmpty ? sourceKey : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCacheSourceKey(
    String cacheKey,
    String? sourceKey,
  ) async {
    if (sourceKey == null) {
      return;
    }
    final metaFile = _cacheMetaFile(cacheKey);
    if (metaFile == null) {
      return;
    }
    await metaFile.writeAsString(
      jsonEncode({
        "sourceUrl": _latestTagsDatabaseUrl,
        "sourceKey": sourceKey,
        "version": _tagsDatabaseVersion,
        "updatedAt": DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
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
      Log.warning("Tags Translation", "Failed to read cached tag data: $e");
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
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return Isolate.run(() => _decodeTagData(bytes));
  }

  static Future<String> _downloadLatestTagData() async {
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
    text = text.toLowerCase();
    if (text != "reclass" && text.endsWith('s')) {
      text.replaceLast('s', '');
    }
    return switch (namespace) {
      "male" => maleTags[text] ?? text,
      "female" => femaleTags[text] ?? text,
      "mixed" => mixedTags[text] ?? text,
      "other" => otherTags[text] ?? text,
      "parody" => parodyTags[text] ?? text,
      "character" => characterTranslations[text] ?? text,
      "group" => groupTags[text] ?? text,
      "cosplayer" => cosplayerTags[text] ?? text,
      "reclass" => reclassTags[text] ?? text,
      "language" => languageTranslations[text] ?? text,
      "artist" => artistTags[text] ?? text,
      _ => text.translateTagsToCN,
    };
  }

  String _categoryTextDynamic(String c) {
    if (App.locale.languageCode == "zh") {
      return translateTagsCategoryToCN;
    } else {
      return this;
    }
  }

  String get categoryTextDynamic => _categoryTextDynamic(this);

  String get translateTagsCategoryToCN =>
      tagsCategoryTranslations[this] ?? this;

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
