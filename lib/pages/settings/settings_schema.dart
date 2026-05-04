part of 'settings_page.dart';

class SettingKey<T> {
  final String name;

  const SettingKey(this.name);
}

abstract final class CommonSettingKeys {
  static const checkUpdateOnStart = SettingKey<bool>('checkUpdateOnStart');
  static const proxy = SettingKey<String>('proxy');
  static const enableDnsOverrides = SettingKey<bool>('enableDnsOverrides');
  static const sni = SettingKey<bool>('sni');
  static const downloadThreads = SettingKey<int>('downloadThreads');
  static const ignoreBadCertificate = SettingKey<bool>('ignoreBadCertificate');
  static const enableDebugDiagnostics = SettingKey<bool>(
    'enableDebugDiagnostics',
  );
  static const readerNextEnabled = SettingKey<bool>('reader_next_enabled');
  static const readerNextHistoryEnabled = SettingKey<bool>(
    'reader_next_history_enabled',
  );
  static const readerNextFavoritesEnabled = SettingKey<bool>(
    'reader_next_favorites_enabled',
  );
  static const readerNextDownloadsEnabled = SettingKey<bool>(
    'reader_next_downloads_enabled',
  );
  static const readerUseSourceRefResolver = SettingKey<bool>(
    'reader_use_source_ref_resolver',
  );
}

abstract final class ExploreSettingKeys {
  static const comicDisplayMode = SettingKey<String>('comicDisplayMode');
  static const comicTileScale = SettingKey<double>('comicTileScale');
  static const showFavoriteStatusOnTile = SettingKey<bool>(
    'showFavoriteStatusOnTile',
  );
  static const showHistoryStatusOnTile = SettingKey<bool>(
    'showHistoryStatusOnTile',
  );
  static const reverseChapterOrder = SettingKey<bool>('reverseChapterOrder');
  static const defaultSearchTarget = SettingKey<String>('defaultSearchTarget');
  static const autoAddLanguageFilter = SettingKey<String>(
    'autoAddLanguageFilter',
  );
  static const initialPage = SettingKey<String>('initialPage');
  static const comicListDisplayMode = SettingKey<String>(
    'comicListDisplayMode',
  );
  static const blockedWords = SettingKey<List<Object>>('blockedWords');
  static const explorePages = SettingKey<List<Object>>('explore_pages');
  static const categories = SettingKey<List<Object>>('categories');
  static const favorites = SettingKey<List<Object>>('favorites');
  static const searchSources = SettingKey<List<Object>>('searchSources');
}

abstract final class ReaderSettingKeys {
  static const readerMode = SettingKey<String>('readerMode');
  static const showChapterComments = SettingKey<bool>('showChapterComments');
  static const showChapterCommentsAtEnd = SettingKey<bool>(
    'showChapterCommentsAtEnd',
  );
  static const readerScreenPicNumberForLandscape = SettingKey<num>(
    'readerScreenPicNumberForLandscape',
  );
  static const readerScreenPicNumberForPortrait = SettingKey<num>(
    'readerScreenPicNumberForPortrait',
  );
}

abstract final class AppearanceSettingKeys {
  static const themeMode = SettingKey<String>('theme_mode');
  static const color = SettingKey<String>('color');
}

abstract final class LocalFavoritesSettingKeys {
  static const localFavoritesFirst = SettingKey<bool>('localFavoritesFirst');
  static const autoCloseFavoritePanel = SettingKey<bool>(
    'autoCloseFavoritePanel',
  );
  static const newFavoriteAddTo = SettingKey<String>('newFavoriteAddTo');
  static const moveFavoriteAfterRead = SettingKey<String>(
    'moveFavoriteAfterRead',
  );
  static const quickFavorite = SettingKey<String>('quickFavorite');
  static const onClickFavorite = SettingKey<String>('onClickFavorite');
}

abstract final class AppSettingKeys {
  static const cacheSize = SettingKey<int>('cacheSize');
  static const authorizationRequired = SettingKey<bool>(
    'authorizationRequired',
  );
  static const webdav = SettingKey<List<Object>>('webdav');
  static const disableSyncFields = SettingKey<String>('disableSyncFields');
  static const language = SettingKey<String>('language');
  static const enableRemoteChineseTextConversion = SettingKey<bool>(
    'enableRemoteChineseTextConversion',
  );
}

abstract final class ImplicitSettingKeys {
  static const webdavAutoSync = SettingKey<bool>('webdavAutoSync');
}
