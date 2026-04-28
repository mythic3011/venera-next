import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import '../foundation/app.dart';

extension AppTranslation on String {
  String _translate() {
    var locale = App.locale;
    var key = "${locale.languageCode}_${locale.countryCode}";
    if (locale.languageCode == "en") {
      key = "en_US";
    }
    final fallbackKeys = <String>[
      key,
      if (key == "zh_HK" || key == "zh_MO") "zh_TW",
      if (locale.languageCode == "zh") "zh_CN",
    ];
    for (final fallbackKey in fallbackKeys) {
      final translated = translations[fallbackKey]?[this];
      if (translated != null) {
        return translated;
      }
    }
    return this;
  }

  String get tl => _translate();

  String get tlEN => translations["en_US"]![this] ?? this;

  String tlParams(Map<String, Object> values) {
    var res = _translate();
    for (var entry in values.entries) {
      res = res.replaceFirst("@${entry.key}", entry.value.toString());
    }
    return res;
  }

  static late final Map<String, Map<String, String>> translations;

  static Future<void> init() async {
    final splitLocales = ["zh_CN", "zh_TW", "zh_HK"];
    final loaded = <String, Map<String, String>>{};
    for (final locale in splitLocales) {
      try {
        final data = await rootBundle.load("assets/i18n/$locale.json");
        final json = jsonDecode(utf8.decode(data.buffer.asUint8List()));
        loaded[locale] = Map<String, String>.from(json);
      } catch (_) {}
    }
    if (loaded.isNotEmpty) {
      translations = loaded;
      return;
    }
    var data = await rootBundle.load("assets/translation.json");
    var json = jsonDecode(utf8.decode(data.buffer.asUint8List()));
    translations = {
      for (var e in json.entries) e.key: Map<String, String>.from(e.value),
    };
  }

  /// Translate a string using specified comic source
  String ts(String sourceKey) {
    var comicSource = ComicSource.find(sourceKey);
    if (comicSource == null || comicSource.translations == null) {
      return this;
    }
    var locale = App.locale;
    var lc = locale.languageCode;
    var cc = locale.countryCode;
    var key = "$lc${cc == null ? "" : "_$cc"}";
    return (comicSource.translations![key] ??
            comicSource.translations![lc])?[this] ??
        this;
  }
}

extension ListTranslation on List<String> {
  List<String> _translate() {
    return List.generate(length, (index) => this[index].tl);
  }

  List<String> get tl => _translate();
}
