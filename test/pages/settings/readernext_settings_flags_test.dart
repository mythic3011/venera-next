import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/pages/settings/settings_page.dart';

void main() {
  test('ReaderNext settings keys are exposed and bool-typed', () {
    final keys = <String>[
      CommonSettingKeys.readerNextEnabled.name,
      CommonSettingKeys.readerNextHistoryEnabled.name,
      CommonSettingKeys.readerNextFavoritesEnabled.name,
      CommonSettingKeys.readerNextDownloadsEnabled.name,
      CommonSettingKeys.readerUseSourceRefResolver.name,
    ];

    for (final key in keys) {
      expect(appdata.settings[key], isA<bool>());
    }
  });

  test('ReaderNext settings keys remain writable', () {
    final originalMaster = appdata.settings[CommonSettingKeys.readerNextEnabled.name];
    final originalHistory =
        appdata.settings[CommonSettingKeys.readerNextHistoryEnabled.name];
    final originalFavorites =
        appdata.settings[CommonSettingKeys.readerNextFavoritesEnabled.name];
    final originalDownloads =
        appdata.settings[CommonSettingKeys.readerNextDownloadsEnabled.name];
    final originalResolver =
        appdata.settings[CommonSettingKeys.readerUseSourceRefResolver.name];

    appdata.settings[CommonSettingKeys.readerNextEnabled.name] = !(originalMaster as bool);
    appdata.settings[CommonSettingKeys.readerNextHistoryEnabled.name] =
        !(originalHistory as bool);
    appdata.settings[CommonSettingKeys.readerNextFavoritesEnabled.name] =
        !(originalFavorites as bool);
    appdata.settings[CommonSettingKeys.readerNextDownloadsEnabled.name] =
        !(originalDownloads as bool);
    appdata.settings[CommonSettingKeys.readerUseSourceRefResolver.name] =
        !(originalResolver as bool);

    expect(appdata.settings[CommonSettingKeys.readerNextEnabled.name], isA<bool>());
    expect(
      appdata.settings[CommonSettingKeys.readerNextHistoryEnabled.name],
      isA<bool>(),
    );
    expect(
      appdata.settings[CommonSettingKeys.readerNextFavoritesEnabled.name],
      isA<bool>(),
    );
    expect(
      appdata.settings[CommonSettingKeys.readerNextDownloadsEnabled.name],
      isA<bool>(),
    );
    expect(
      appdata.settings[CommonSettingKeys.readerUseSourceRefResolver.name],
      isA<bool>(),
    );

    appdata.settings[CommonSettingKeys.readerNextEnabled.name] = originalMaster;
    appdata.settings[CommonSettingKeys.readerNextHistoryEnabled.name] =
        originalHistory;
    appdata.settings[CommonSettingKeys.readerNextFavoritesEnabled.name] =
        originalFavorites;
    appdata.settings[CommonSettingKeys.readerNextDownloadsEnabled.name] =
        originalDownloads;
    appdata.settings[CommonSettingKeys.readerUseSourceRefResolver.name] =
        originalResolver;
  });
}

