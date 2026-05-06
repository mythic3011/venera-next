library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/sources/identity/source_identity.dart';
import 'package:venera/features/sources/comic_source/runtime.dart';
import 'package:venera/features/sources/comic_source/runtime/source_capability_policy.dart';
import 'package:venera/pages/category_comics_page.dart';
import 'package:venera/pages/search_result_page.dart';
import 'package:venera/utils/data_sync.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/init.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';

import 'package:venera/foundation/js/js_engine.dart';

part 'category.dart';

part 'favorites.dart';

part 'parser.dart';

part 'models.dart';

part 'types.dart';

class ComicSourceManager with ChangeNotifier, Init {
  final List<ComicSource> _sources = [];

  static ComicSourceManager? _instance;

  ComicSourceManager._create();

  factory ComicSourceManager() => _instance ??= ComicSourceManager._create();

  List<ComicSource> all() => List.from(_sources);

  bool _isCanonicalSourceKey(String key) {
    final trimmed = key.trim();
    return trimmed.isNotEmpty && !trimmed.contains(':');
  }

  ComicSource? findCanonical(String key) {
    if (!_isCanonicalSourceKey(key)) {
      AppDiagnostics.warn(
        'source.runtime',
        'Rejected non-canonical source key lookup',
        data: {'sourceKey': key},
      );
      return null;
    }
    final exact = _sources.firstWhereOrNull((element) => element.key == key);
    if (exact != null) {
      return exact;
    }
    return _sources.firstWhereOrNull(
      (element) => element.identity.matchesKey(key),
    );
  }

  ComicSource? find(String key) => findCanonical(key);

  ComicSource? fromIntKey(int key) => _sources.firstWhereOrNull(
    (element) => matchesSourceIdentityTypeValue(
      identity: element.identity,
      typeValue: key,
    ),
  );

  @override
  @protected
  Future<void> doInit() async {
    await JsEngine().ensureInit();
    final path = "${App.dataPath}/comic_source";
    if (!(await Directory(path).exists())) {
      Directory(path).create();
      return;
    }
    await for (var entity in Directory(path).list()) {
      if (entity is File && entity.path.endsWith(".js")) {
        try {
          var source = await ComicSourceParser().parse(
            await entity.readAsString(),
            entity.absolute.path,
          );
          _sources.add(source);
        } catch (e, s) {
          AppDiagnostics.error(
            'source.runtime',
            e,
            stackTrace: s,
            message: 'Failed to parse comic source',
            data: {'stage': 'parseSourceFile', 'path': entity.absolute.path},
          );
          AppDiagnostics.error('source.runtime', e, stackTrace: s);
        }
      }
    }
    _refreshTrustedSourceCapabilities();
  }

  Future reload() async {
    _sources.clear();
    JsEngine().runCode("ComicSource.sources = {};");
    await doInit();
    notifyListeners();
  }

  void add(ComicSource source) {
    _sources.add(source);
    _refreshTrustedSourceCapabilities();
    notifyListeners();
  }

  void remove(String key) {
    if (!_isCanonicalSourceKey(key)) {
      AppDiagnostics.warn(
        'source.runtime',
        'Rejected non-canonical source key remove',
        data: {'sourceKey': key},
      );
      return;
    }
    _sources.removeWhere((element) => element.key == key);
    _refreshTrustedSourceCapabilities();
    notifyListeners();
  }

  bool get isEmpty => _sources.isEmpty;

  /// Key is the source key, value is the version.
  final _availableUpdates = <String, String>{};

  void updateAvailableUpdates(Map<String, String> updates) {
    _availableUpdates.addAll(updates);
    notifyListeners();
  }

  Map<String, String> get availableUpdates => Map.from(_availableUpdates);

  void notifyStateChange() {
    notifyListeners();
  }

  void _refreshTrustedSourceCapabilities() {
    final denied = _sources
        .where((source) => !source.securityCapabilities.allowSensitiveCrypto)
        .map((source) => source.key);
    final trusted = buildTrustedCryptoSourceKeys(
      sourceKeys: _sources.map((s) => s.key),
      deniedSourceKeys: denied,
      mandatorySourceKey: localSourceKey,
    );
    configureTrustedCryptoSources(trusted);
  }
}

class ComicSource {
  static List<ComicSource> all() => ComicSourceManager().all();

  static ComicSource? find(String key) =>
      ComicSourceManager().findCanonical(key);

  static ComicSource? fromIntKey(int key) =>
      ComicSourceManager().fromIntKey(key);

  static bool get isEmpty => ComicSourceManager().isEmpty;

  /// Name of this source.
  final String name;

  /// Identifier of this source.
  final String key;

  final SourceIdentity identity;

  int get intKey {
    return identity.typeValue;
  }

  ComicType get comicType => ComicType(intKey);

  /// Account config.
  final AccountConfig? account;

  /// Category data used to build a static category tags page.
  final CategoryData? categoryData;

  /// Category comics data used to build a comics page with a category tag.
  final CategoryComicsData? categoryComicsData;

  /// Favorite data used to build favorite page.
  final FavoriteData? favoriteData;

  /// Explore pages.
  final List<ExplorePageData> explorePages;

  /// Search page.
  final SearchPageData? searchPageData;

  /// Load comic info.
  final LoadComicFunc? loadComicInfo;

  final ComicThumbnailLoader? loadComicThumbnail;

  /// Load comic pages.
  final LoadComicPagesFunc? loadComicPages;

  final GetImageLoadingConfigFunc? getImageLoadingConfig;

  final Map<String, dynamic> Function(String imageKey)?
  getThumbnailLoadingConfig;

  var data = <String, dynamic>{};

  SourceSecurityCapabilities get securityCapabilities =>
      SourceSecurityCapabilities.fromData(data);

  bool get isLogged => data["account"] != null;

  final String filePath;

  final String url;

  final String version;

  final CommentsLoader? commentsLoader;

  final SendCommentFunc? sendCommentFunc;

  final ChapterCommentsLoader? chapterCommentsLoader;

  final SendChapterCommentFunc? sendChapterCommentFunc;

  final RegExp? idMatcher;

  final LikeOrUnlikeComicFunc? likeOrUnlikeComic;

  final VoteCommentFunc? voteCommentFunc;

  final LikeCommentFunc? likeCommentFunc;

  final Map<String, Map<String, dynamic>>? settings;

  final Map<String, Map<String, String>>? translations;

  final HandleClickTagEvent? handleClickTagEvent;

  /// Callback when a tag suggestion is selected in search.
  final TagSuggestionSelectFunc? onTagSuggestionSelected;

  final LinkHandler? linkHandler;

  final bool enableTagsSuggestions;

  final bool enableTagsTranslate;

  final StarRatingFunc? starRatingFunc;

  final ArchiveDownloader? archiveDownloader;

  Future<void> loadData() async {
    final file = File("${App.dataPath}/comic_source/$key.data");
    if (!await file.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('source data must be object');
      }
      data = Map<String, dynamic>.from(decoded);
    } catch (e, s) {
      AppDiagnostics.warn(
        'source.runtime',
        'Invalid source data payload, fallback to empty data',
        data: {'sourceKey': key, 'stage': 'loadSourceData', 'error': '$e'},
      );
      AppDiagnostics.error(
        'source.runtime',
        e,
        stackTrace: s,
        message: 'load_source_data_failed',
      );
      data = <String, dynamic>{};
    }
  }

  bool _isSaving = false;
  bool _haveWaitingTask = false;

  Future<void> saveData() async {
    if (_isSaving) {
      _haveWaitingTask = true;
      return;
    }
    _isSaving = true;
    try {
      do {
        _haveWaitingTask = false;
        final file = File("${App.dataPath}/comic_source/$key.data");
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        await file.writeAsString(jsonEncode(data));
      } while (_haveWaitingTask);
    } finally {
      _isSaving = false;
    }
    DataSync().uploadData();
  }

  Future<bool> reLogin() async {
    if (data["account"] == null) {
      return false;
    }
    final List accountData = data["account"];
    var res = await account!.login!(accountData[0], accountData[1]);
    if (res.error) {
      AppDiagnostics.warn(
        'source.runtime',
        'Failed to re-login',
        data: {
          'sourceKey': key,
          'stage': 'reLogin',
          'errorMessage': res.errorMessage,
        },
      );
      AppDiagnostics.error(
        'source.runtime',
        res.errorMessage ?? 'Error',
        message: 'relogin_failed',
      );
    }
    return !res.error;
  }

  /// Get settings dynamically from JavaScript source.
  /// This allows sources to use getters for dynamic settings that can change at runtime.
  Map<String, Map<String, dynamic>>? getSettingsDynamic() {
    final context = SourceRuntimeBoundary.newContext(sourceKey: key);
    try {
      final safeKey = jsonEncode(key);
      var value = JsEngine().runCode("ComicSource.sources[$safeKey]?.settings");
      if (value != null && value is! Map) {
        final mapped = LegacySourceDiagnosticsAdapter.mapException(
          error: SourceRuntimeBoundary.invalidSettingsShape(
            context: context,
            rawValue: value,
          ),
          context: context,
          stageOverride: SourceRuntimeStage.parser,
          codeOverride: SourceRuntimeCodes.settingsInvalid,
          messageOverride: 'Invalid dynamic settings shape.',
        );
        AppDiagnostics.error(
          'source.runtime',
          mapped.toDiagnosticJson(),
          message: 'load_dynamic_settings_failed',
        );
        return settings;
      }
      if (value is Map) {
        var newMap = <String, Map<String, dynamic>>{};
        for (var e in value.entries) {
          if (e.key is! String) {
            continue;
          }
          var v = <String, dynamic>{};
          for (var e2 in e.value.entries) {
            if (e2.key is! String) {
              continue;
            }
            var v2 = e2.value;
            if (v2 is JSInvokable) {
              v2 = JSAutoFreeFunction(v2);
            }
            v[e2.key] = v2;
          }
          newMap[e.key] = v;
        }
        return newMap;
      }
      return null;
    } catch (e, s) {
      final mapped = LegacySourceDiagnosticsAdapter.mapException(
        error: e,
        context: context,
        stageOverride: SourceRuntimeStage.parser,
      );
      AppDiagnostics.error(
        'source.runtime',
        mapped.toDiagnosticJson(),
        stackTrace: s,
        message: 'failed_to_get_dynamic_settings',
      );
      AppDiagnostics.error(
        'source.runtime',
        mapped.toUiMessage(),
        stackTrace: s,
        message: 'load_dynamic_settings_failed',
      );
      return settings;
    }
  }

  ComicSource(
    this.name,
    this.key,
    this.account,
    this.categoryData,
    this.categoryComicsData,
    this.favoriteData,
    this.explorePages,
    this.searchPageData,
    this.settings,
    this.loadComicInfo,
    this.loadComicThumbnail,
    this.loadComicPages,
    this.getImageLoadingConfig,
    this.getThumbnailLoadingConfig,
    this.filePath,
    this.url,
    this.version,
    this.commentsLoader,
    this.sendCommentFunc,
    this.chapterCommentsLoader,
    this.sendChapterCommentFunc,
    this.likeOrUnlikeComic,
    this.voteCommentFunc,
    this.likeCommentFunc,
    this.idMatcher,
    this.translations,
    this.handleClickTagEvent,
    this.onTagSuggestionSelected,
    this.linkHandler,
    this.enableTagsSuggestions,
    this.enableTagsTranslate,
    this.starRatingFunc,
    this.archiveDownloader, {
    SourceIdentity? identity,
  }) : identity =
           identity ??
           sourceIdentityFromKey(key, names: [name], version: version);
}

class SourceSecurityCapabilities {
  final bool allowSensitiveCrypto;

  const SourceSecurityCapabilities({required this.allowSensitiveCrypto});

  factory SourceSecurityCapabilities.fromData(Map<String, dynamic> data) {
    final raw = data[sourceSecurityField];
    if (raw is! Map) {
      return const SourceSecurityCapabilities(allowSensitiveCrypto: false);
    }
    final security = Map<String, dynamic>.from(raw);
    final allow = security[allowSensitiveCryptoField];
    if (allow is bool) {
      return SourceSecurityCapabilities(allowSensitiveCrypto: allow);
    }
    return const SourceSecurityCapabilities(allowSensitiveCrypto: false);
  }
}

class AccountConfig {
  final LoginFunction? login;

  final String? loginWebsite;

  final String? registerWebsite;

  final void Function() logout;

  final List<AccountInfoItem> infoItems;

  final bool Function(String url, String title)? checkLoginStatus;

  final void Function()? onLoginWithWebviewSuccess;

  final List<String>? cookieFields;

  final Future<bool> Function(List<String>)? validateCookies;

  const AccountConfig(
    this.login,
    this.loginWebsite,
    this.registerWebsite,
    this.logout,
    this.checkLoginStatus,
    this.onLoginWithWebviewSuccess,
    this.cookieFields,
    this.validateCookies,
  ) : infoItems = const [];
}

class AccountInfoItem {
  final String title;
  final String Function()? data;
  final void Function()? onTap;
  final WidgetBuilder? builder;

  AccountInfoItem({required this.title, this.data, this.onTap, this.builder});
}

class LoadImageRequest {
  String url;

  Map<String, String> headers;

  LoadImageRequest(this.url, this.headers);
}

class ExplorePageData {
  final String title;

  final ExplorePageType type;

  final ComicListBuilder? loadPage;

  final ComicListBuilderWithNext? loadNext;

  final Future<Res<List<ExplorePagePart>>> Function()? loadMultiPart;

  /// return a `List` contains `List<Comic>` or `ExplorePagePart`
  final Future<Res<List<Object>>> Function(int index)? loadMixed;

  ExplorePageData(
    this.title,
    this.type,
    this.loadPage,
    this.loadNext,
    this.loadMultiPart,
    this.loadMixed,
  );
}

class ExplorePagePart {
  final String title;

  final List<Comic> comics;

  /// If this is not null, the [ExplorePagePart] will show a button to jump to new page.
  ///
  /// Value of this field should match the following format:
  ///   - search:keyword
  ///   - category:categoryName
  ///
  /// End with `@`+`param` if the category has a parameter.
  final PageJumpTarget? viewMore;

  const ExplorePagePart(this.title, this.comics, this.viewMore);
}

enum ExplorePageType {
  multiPageComicList,
  singlePageWithMultiPart,
  mixed,
  override,
}

typedef SearchFunction =
    Future<Res<List<Comic>>> Function(
      String keyword,
      int page,
      List<String> searchOption,
    );

typedef SearchNextFunction =
    Future<Res<List<Comic>>> Function(
      String keyword,
      String? next,
      List<String> searchOption,
    );

class SearchPageData {
  /// If this is not null, the default value of search options will be first element.
  final List<SearchOptions>? searchOptions;

  final SearchFunction? loadPage;

  final SearchNextFunction? loadNext;

  const SearchPageData(this.searchOptions, this.loadPage, this.loadNext);
}

class SearchOptions {
  final LinkedHashMap<String, String> options;

  final String label;

  final String type;

  final String? defaultVal;

  const SearchOptions(this.options, this.label, this.type, this.defaultVal);

  String get defaultValue => defaultVal ?? options.keys.firstOrNull ?? "";
}

typedef CategoryComicsLoader =
    Future<Res<List<Comic>>> Function(
      String category,
      String? param,
      List<String> options,
      int page,
    );

typedef CategoryOptionsLoader =
    Future<Res<List<CategoryComicsOptions>>> Function(
      String category,
      String? param,
    );

class CategoryComicsData {
  /// options
  final List<CategoryComicsOptions>? options;

  final CategoryOptionsLoader? optionsLoader;

  /// [category] is the one clicked by the user on the category page.
  ///
  /// if [BaseCategoryPart.categoryParams] is not null, [param] will be not null.
  ///
  /// [Res.subData] should be maxPage or null if there is no limit.
  final CategoryComicsLoader load;

  final RankingData? rankingData;

  const CategoryComicsData({
    this.options,
    this.optionsLoader,
    required this.load,
    this.rankingData,
  });
}

class RankingData {
  final Map<String, String> options;

  final Future<Res<List<Comic>>> Function(String option, int page)? load;

  final Future<Res<List<Comic>>> Function(String option, String? next)?
  loadWithNext;

  const RankingData(this.options, this.load, this.loadWithNext);
}

class CategoryComicsOptions {
  // The label will not be displayed if it is empty.
  final String label;

  /// Use a [LinkedHashMap] to describe an option list.
  /// key is for loading comics, value is the name displayed on screen.
  /// Default value will be the first of the Map.
  final LinkedHashMap<String, String> options;

  /// If [notShowWhen] contains category's name, the option will not be shown.
  final List<String> notShowWhen;

  final List<String>? showWhen;

  const CategoryComicsOptions(
    this.label,
    this.options,
    this.notShowWhen,
    this.showWhen,
  );
}

class LinkHandler {
  final List<String> domains;

  final String? Function(String url) linkToId;

  const LinkHandler(this.domains, this.linkToId);
}

class ArchiveDownloader {
  final Future<Res<List<ArchiveInfo>>> Function(String cid) getArchives;

  final Future<Res<String>> Function(String cid, String aid) getDownloadUrl;

  const ArchiveDownloader(this.getArchives, this.getDownloadUrl);
}
