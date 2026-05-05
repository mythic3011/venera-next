import 'package:flutter/widgets.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/opencc.dart';

typedef ChineseTextConverter = String Function(String input);

enum RemoteTextSurface {
  tagLabel,
  categoryLabel,
  commandLabel,
  sourceButtonLabel,
  menuLabel,
  sectionTitle,
  jsDialogTitle,
  jsActionLabel,
  jsSelectOptionLabel,
}

abstract final class RemoteTextNormalizer {
  static final RegExp _windowsPathPattern = RegExp(r'^[A-Za-z]:\\');
  static final RegExp _fileLikePattern = RegExp(
    r'\.(js|json|html|htm|jpg|jpeg|png|webp|gif|zip|rar|7z|pdf|txt|md)$',
    caseSensitive: false,
  );

  static String normalizeLabel(
    String value, {
    required RemoteTextSurface surface,
    required Locale locale,
    bool? enabled,
    ChineseTextConverter? s2t,
    ChineseTextConverter? t2s,
  }) {
    if (!_isEnabled(enabled)) {
      return value;
    }
    if (locale.languageCode != 'zh') {
      return value;
    }
    if (_shouldBypass(value)) {
      return value;
    }

    final direction = _resolveDirection(locale);
    if (direction == null) {
      return value;
    }

    final converter = switch (direction) {
      _TextDirection.toTraditional => s2t ?? OpenCC.simplifiedToTraditional,
      _TextDirection.toSimplified => t2s ?? OpenCC.traditionalToSimplified,
    };

    try {
      return converter(value);
    } catch (error) {
      AppDiagnostics.warn(
        'text.normalization',
        'text.normalization.failed',
        data: {
          'surface': surface.name,
          'locale': locale.toLanguageTag(),
          'direction': direction.name,
          'inputLength': value.length,
          'source': 'remote_label',
          'errorType': error.runtimeType.toString(),
        },
      );
      return value;
    }
  }

  static bool _isEnabled(bool? enabled) {
    if (enabled != null) {
      return enabled;
    }
    return appdata.settings[AppSettingKeys
            .enableRemoteChineseTextConversion
            .name] ==
        true;
  }

  static _TextDirection? _resolveDirection(Locale locale) {
    final script = locale.scriptCode?.toLowerCase();
    final country = locale.countryCode?.toUpperCase();
    if (script == 'hant' || country == 'HK' || country == 'TW') {
      return _TextDirection.toTraditional;
    }
    if (script == 'hans' || country == 'CN' || country == 'SG') {
      return _TextDirection.toSimplified;
    }
    return null;
  }

  static bool _shouldBypass(String value) {
    if (value.trim().isEmpty) {
      return true;
    }
    if (value.runes.every((rune) => rune <= 0x7F)) {
      return true;
    }
    if (_looksLikeUri(value)) {
      return true;
    }
    if (value.startsWith('/')) {
      return true;
    }
    if (_windowsPathPattern.hasMatch(value)) {
      return true;
    }
    if (value.contains(r'\')) {
      return true;
    }
    if (value.contains('./') || value.contains('../')) {
      return true;
    }
    if (_fileLikePattern.hasMatch(value.trim())) {
      return true;
    }
    if (_looksLikeCode(value)) {
      return true;
    }
    return false;
  }

  static bool _looksLikeUri(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri?.hasScheme == true;
  }

  static bool _looksLikeCode(String value) {
    return value.contains('function(') ||
        value.contains('=>') ||
        value.contains('{') ||
        value.contains('}') ||
        value.contains(r'$.') ||
        value.contains('document.') ||
        value.contains('querySelector');
  }
}

enum _TextDirection { toTraditional, toSimplified }
