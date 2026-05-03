part of 'comic_source.dart';

/// return true if ver1 > ver2
bool compareSemVer(String ver1, String ver2) {
  ver1 = ver1.replaceFirst("-", ".");
  ver2 = ver2.replaceFirst("-", ".");
  List<String> v1 = ver1.split('.');
  List<String> v2 = ver2.split('.');

  for (int i = 0; i < 3; i++) {
    int num1 = int.parse(v1[i]);
    int num2 = int.parse(v2[i]);

    if (num1 > num2) {
      return true;
    } else if (num1 < num2) {
      return false;
    }
  }

  var v14 = v1.elementAtOrNull(3);
  var v24 = v2.elementAtOrNull(3);

  if (v14 != v24) {
    if (v14 == null && v24 != "hotfix") {
      return true;
    } else if (v14 == null) {
      return false;
    }
    if (v24 == null) {
      if (v14 == "hotfix") {
        return true;
      }
      return false;
    }
    return v14.compareTo(v24) > 0;
  }

  return false;
}

class ComicSourceParseException implements Exception {
  final String message;

  ComicSourceParseException(this.message);

  @override
  String toString() {
    return message;
  }
}

class ComicSourceParser {
  static const _jsonKeyComics = 'comics';
  static const _jsonKeyNext = 'next';
  static const _jsonKeyData = 'data';
  static const _jsonKeyTitle = 'title';
  static const _jsonKeyViewMore = 'viewMore';
  static const _jsonKeyMaxPage = 'maxPage';
  static const _jsonKeyThumbnails = 'thumbnails';
  static const _jsonKeyEnableRankingPage = 'enableRankingPage';

  static const _identityField = 'identity';
  static const _sourceIdField = 'sourceId';
  static const _identityIdField = 'id';
  static const _identityKindField = 'kind';
  static const _identityAliasesField = 'aliases';
  static const _identityNamesField = 'names';
  static const _identityVersionField = 'version';

  static const _tempInstance = "this['temp']";
  static const _sourceRootPrefix = "ComicSource.sources";

  /// comic source key
  String? _key;

  String? _name;

  Future<ComicSource> createAndParse(String js, String fileName) async {
    if (!fileName.endsWith("js")) {
      fileName = "$fileName.js";
    }
    var file = File(FilePath.join(App.dataPath, "comic_source", fileName));
    if (file.existsSync()) {
      int i = 0;
      while (file.existsSync()) {
        file = File(
          FilePath.join(
            App.dataPath,
            "comic_source",
            "${fileName.split('.').first}($i).js",
          ),
        );
        i++;
      }
    }
    await file.writeAsString(js);
    try {
      return await parse(js, file.path);
    } catch (e) {
      await file.delete();
      rethrow;
    }
  }

  Future<ComicSource> parse(String js, String filePath) async {
    js = js.replaceAll("\r\n", "\n");
    var line1 = js
        .split('\n')
        .firstWhereOrNull((e) => e.trim().startsWith("class "));
    if (line1 == null ||
        !line1.startsWith("class ") ||
        !line1.contains("extends ComicSource")) {
      throw ComicSourceParseException("Invalid Content");
    }
    var className = line1.split("class")[1].split("extends ComicSource").first;
    className = className.trim();
    JsEngine().runCode("""(() => { $js
        $_tempInstance = new $className()
      }).call()
    """, className);
    _name = _readTempRequiredString('name', 'name is required');
    var key = _readTempRequiredString('key', 'key is required');
    var version = _readTempRequiredString('version', 'version is required');
    var minAppVersion = _readTempString('minAppVersion');
    var url = _readTempString('url');
    final resolvedVersion = version;
    final identity = _loadSourceIdentity(
      key: key,
      name: _name!,
      version: resolvedVersion,
      filePath: filePath,
    );
    if (minAppVersion != null) {
      if (compareSemVer(minAppVersion, App.version.split('-').first)) {
        throw ComicSourceParseException(
          "minAppVersion @version is required".tlParams({
            "version": minAppVersion,
          }),
        );
      }
    }
    for (var source in ComicSource.all()) {
      if (source.key == key) {
        throw ComicSourceParseException("key($key) already exists");
      }
      if (source.identity.id == identity.id) {
        throw ComicSourceParseException(
          "source identity id(${identity.id}) already exists",
        );
      }
    }
    _key = key;
    _checkKeyValidation();

    JsEngine().runCode("""$_sourceRootPrefix.$_key = $_tempInstance;""");

    var source = ComicSource(
      _name!,
      key,
      _loadAccountConfig(),
      _loadCategoryData(),
      _loadCategoryComicsData(),
      _loadFavoriteData(),
      _loadExploreData(),
      _loadSearchData(),
      _parseSettings(),
      _parseLoadComicFunc(),
      _parseThumbnailLoader(),
      _parseLoadComicPagesFunc(),
      _parseImageLoadingConfigFunc(),
      _parseThumbnailLoadingConfigFunc(),
      filePath,
      url ?? "",
      resolvedVersion,
      _parseCommentsLoader(),
      _parseSendCommentFunc(),
      _parseChapterCommentsLoader(),
      _parseSendChapterCommentFunc(),
      _parseLikeFunc(),
      _parseVoteCommentFunc(),
      _parseLikeCommentFunc(),
      _parseIdMatch(),
      _parseTranslation(),
      _parseClickTagEvent(),
      _parseTagSuggestionSelectFunc(),
      _parseLinkHandler(),
      _getValueAs<bool>("search.enableTagsSuggestions") ?? false,
      _getValueAs<bool>("comic.enableTagsTranslate") ?? false,
      _parseStarRatingFunc(),
      _parseArchiveDownloader(),
      identity: identity,
    );

    await source.loadData();

    if (_checkExists("init")) {
      Future.delayed(const Duration(milliseconds: 50), () {
        JsEngine().runCode("ComicSource.sources.$_key.init()");
      });
    }

    return source;
  }

  _checkKeyValidation() {
    // 仅允许数字和字母以及下划线
    if (!_key!.contains(RegExp(r"^[a-zA-Z0-9_]+$"))) {
      throw ComicSourceParseException("key $_key is invalid");
    }
  }

  SourceIdentity _loadSourceIdentity({
    required String key,
    required String name,
    required String version,
    required String filePath,
  }) {
    final rawIdentity = _readTempValue(_identityField);
    final rawSourceId = _readTempValue(_sourceIdField);
    if (rawIdentity != null && rawIdentity is! Map) {
      throw ComicSourceParseException('identity must be an object');
    }
    if (rawSourceId != null && rawSourceId is! String) {
      throw ComicSourceParseException('sourceId must be a string');
    }
    final identityMap = rawIdentity is Map
        ? Map<String, dynamic>.from(rawIdentity)
        : const <String, dynamic>{};
    final identityId =
        (identityMap[_identityIdField] as String?) ??
        (rawSourceId as String?) ??
        key;
    if (!identityId.contains(RegExp(r"^[a-zA-Z0-9_]+$"))) {
      throw ComicSourceParseException("identity id $identityId is invalid");
    }
    final aliases = identityMap[_identityAliasesField];
    final names = identityMap[_identityNamesField];
    return SourceIdentity.legacy(
      key: key,
      id: identityId,
      kind: identityMap[_identityKindField] as String? ?? remoteSourceKind,
      aliases: aliases is List ? aliases.whereType<String>() : const <String>[],
      names: [name, if (names is List) ...names.whereType<String>()],
      version: identityMap[_identityVersionField] as String? ?? version,
      audit: SourceIdentityAudit(
        source: 'comic_source_parser',
        loadedFrom: filePath,
        declaredVersion: version,
      ),
    );
  }

  bool _checkExists(String index) {
    return JsEngine().runCode(
          "${_sourceExpr(index)} !== null && ${_sourceExpr(index)} !== undefined",
        )
        as bool;
  }

  T? _getValueAs<T>(String index) {
    final value = JsEngine().runCode(_sourceExpr(index));
    return value is T ? value : null;
  }

  dynamic _getValue(String index) {
    return JsEngine().runCode(_sourceExpr(index));
  }

  String _sourceExpr(String index) => "$_sourceRootPrefix.$_key.$index";

  dynamic _readTempValue(String field) {
    return JsEngine().runCode("$_tempInstance.$field");
  }

  String? _readTempString(String field) {
    final value = _readTempValue(field);
    return value is String ? value : null;
  }

  String _readTempRequiredString(String field, String error) {
    final value = _readTempValue(field);
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ComicSourceParseException(error);
  }

  AccountConfig? _loadAccountConfig() {
    if (!_checkExists("account")) {
      return null;
    }

    Future<Res<bool>> Function(String account, String pwd)? login;

    if (_checkExists("account.login")) {
      login = (account, pwd) async {
        try {
          await JsEngine().runCode("""
          ComicSource.sources.$_key.account.login(${jsonEncode(account)},
          ${jsonEncode(pwd)})
        """);
          var source = ComicSource.find(_key!)!;
          source.data["account"] = <String>[account, pwd];
          source.saveData();
          return const Res(true);
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      };
    }

    void logout() {
      JsEngine().runCode("ComicSource.sources.$_key.account.logout()");
    }

    bool Function(String url, String title)? checkLoginStatus;

    void Function()? onLoginSuccess;

    if (_checkExists('account.loginWithWebview')) {
      checkLoginStatus = (url, title) {
        return JsEngine().runCode("""
            ComicSource.sources.$_key.account.loginWithWebview.checkStatus(
              ${jsonEncode(url)}, ${jsonEncode(title)})
          """);
      };

      if (_checkExists('account.loginWithWebview.onLoginSuccess')) {
        onLoginSuccess = () {
          JsEngine().runCode("""
            ComicSource.sources.$_key.account.loginWithWebview.onLoginSuccess()
          """);
        };
      }
    }

    Future<bool> Function(List<String>)? validateCookies;

    if (_checkExists('account.loginWithCookies?.validate')) {
      validateCookies = (cookies) async {
        try {
          var res = await JsEngine().runCode("""
            ComicSource.sources.$_key.account.loginWithCookies.validate(${jsonEncode(cookies)})
          """);
          return res;
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return false;
        }
      };
    }

    return AccountConfig(
      login,
      _getValue("account.loginWithWebview?.url"),
      _getValue("account.registerWebsite"),
      logout,
      checkLoginStatus,
      onLoginSuccess,
      ListOrNull.from(_getValue("account.loginWithCookies?.fields")),
      validateCookies,
    );
  }

  List<ExplorePageData> _loadExploreData() {
    if (!_checkExists("explore")) {
      return const [];
    }
    var length = JsEngine().runCode("ComicSource.sources.$_key.explore.length");
    var pages = <ExplorePageData>[];
    for (int i = 0; i < length; i++) {
      final String title = _getValue("explore[$i].title");
      final String type = _getValue("explore[$i].type");
      Future<Res<List<ExplorePagePart>>> Function()? loadMultiPart;
      Future<Res<List<Comic>>> Function(int page)? loadPage;
      Future<Res<List<Comic>>> Function(String? next)? loadNext;
      Future<Res<List<Object>>> Function(int index)? loadMixed;
      if (type == "singlePageWithMultiPart") {
        loadMultiPart = () async {
          try {
            var res = await JsEngine().runCode(
              "ComicSource.sources.$_key.explore[$i].load()",
            );
            return Res(
              List.from(
                res.keys
                    .map(
                      (e) => ExplorePagePart(
                        e,
                        (res[e] as List)
                            .map<Comic>((e) => Comic.fromJson(e, _key!))
                            .toList(),
                        null,
                      ),
                    )
                    .toList(),
              ),
            );
          } catch (e, s) {
            AppDiagnostics.error('source.data_analysis', e, stackTrace: s);
            return Res.error(e.toString());
          }
        };
      } else if (type == "multiPageComicList") {
        if (_checkExists("explore[$i].load")) {
          loadPage = (int page) async {
            try {
              var res = await JsEngine().runCode(
                "ComicSource.sources.$_key.explore[$i].load(${jsonEncode(page)})",
              );
              return Res(
                List.generate(
                  res["comics"].length,
                  (index) => Comic.fromJson(res["comics"][index], _key!),
                ),
                subData: res["maxPage"],
              );
            } catch (e, s) {
              AppDiagnostics.error('source.network', e, stackTrace: s);
              return Res.error(e.toString());
            }
          };
        } else {
          loadNext = (next) async {
            try {
              var res = await JsEngine().runCode(
                "ComicSource.sources.$_key.explore[$i].loadNext(${jsonEncode(next)})",
              );
              return Res(
                List.generate(
                  res[_jsonKeyComics].length,
                  (index) => Comic.fromJson(res[_jsonKeyComics][index], _key!),
                ),
                subData: res[_jsonKeyNext],
              );
            } catch (e, s) {
              AppDiagnostics.error('source.network', e, stackTrace: s);
              return Res.error(e.toString());
            }
          };
        }
      } else if (type == "multiPartPage") {
        loadMultiPart = () async {
          try {
            var res = await JsEngine().runCode(
              "ComicSource.sources.$_key.explore[$i].load()",
            );
            return Res(
              List.from(
                (res as List).map((e) {
                  return ExplorePagePart(
                    e['title'],
                    (e[_jsonKeyComics] as List).map((e) {
                      return Comic.fromJson(e, _key!);
                    }).toList(),
                    PageJumpTarget.parse(_key!, e[_jsonKeyViewMore]),
                  );
                }),
              ),
            );
          } catch (e, s) {
            AppDiagnostics.error('source.data_analysis', e, stackTrace: s);
            return Res.error(e.toString());
          }
        };
      } else if (type == 'mixed') {
        loadMixed = (index) async {
          try {
            var res = await JsEngine().runCode(
              "ComicSource.sources.$_key.explore[$i].load(${jsonEncode(index)})",
            );
            var list = <Object>[];
            for (var data in (res[_jsonKeyData] as List)) {
              if (data is List) {
                list.add(data.map((e) => Comic.fromJson(e, _key!)).toList());
              } else if (data is Map) {
                list.add(
                  ExplorePagePart(
                    data[_jsonKeyTitle],
                    (data[_jsonKeyComics] as List).map((e) {
                      return Comic.fromJson(e, _key!);
                    }).toList(),
                    data[_jsonKeyViewMore],
                  ),
                );
              }
            }
            return Res(list, subData: res[_jsonKeyMaxPage]);
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        };
      }
      pages.add(
        ExplorePageData(
          title,
          switch (type) {
            "singlePageWithMultiPart" =>
              ExplorePageType.singlePageWithMultiPart,
            "multiPartPage" => ExplorePageType.singlePageWithMultiPart,
            "multiPageComicList" => ExplorePageType.multiPageComicList,
            "mixed" => ExplorePageType.mixed,
            _ => throw ComicSourceParseException(
              "Unknown explore page type $type",
            ),
          },
          loadPage,
          loadNext,
          loadMultiPart,
          loadMixed,
        ),
      );
    }
    return pages;
  }

  CategoryData? _loadCategoryData() {
    var doc = _getValue("category");

    if (doc?[_jsonKeyTitle] == null) {
      return null;
    }

    final String title = doc[_jsonKeyTitle];
    final bool? enableRankingPage = doc[_jsonKeyEnableRankingPage];

    var categoryParts = <BaseCategoryPart>[];

    for (var c in doc["parts"]) {
      if (c["categories"] != null && c["categories"] is! List) {
        continue;
      }
      List? categories = c["categories"];
      if (categories == null || categories[0] is Map) {
        // new format
        final String name = c["name"];
        final String type = c["type"];
        final cs = categories
            ?.map(
              (e) => CategoryItem(
                e['label'],
                PageJumpTarget.parse(_key!, e['target']),
              ),
            )
            .toList();
        if (type != "dynamic" && (cs == null || cs.isEmpty)) {
          continue;
        }
        if (type == "fixed") {
          categoryParts.add(FixedCategoryPart(name, cs!));
        } else if (type == "random") {
          categoryParts.add(
            RandomCategoryPart(name, cs!, c["randomNumber"] ?? 1),
          );
        } else if (type == "dynamic" && categories == null) {
          var loader = c["loader"];
          if (loader is! JSInvokable) {
            throw "DynamicCategoryPart loader must be a function";
          }
          categoryParts.add(
            DynamicCategoryPart(name, JSAutoFreeFunction(loader), _key!),
          );
        }
      } else {
        // old format
        final String name = c["name"];
        final String type = c["type"];
        final List<String> tags = List.from(c["categories"]);
        final String itemType = c["itemType"];
        List<String>? categoryParams = ListOrNull.from(c["categoryParams"]);
        final String? groupParam = c["groupParam"];
        if (groupParam != null) {
          categoryParams = List.filled(tags.length, groupParam);
        }
        var cs = <CategoryItem>[];
        for (int i = 0; i < tags.length; i++) {
          PageJumpTarget target;
          if (itemType == 'category') {
            target = PageJumpTarget(_key!, 'category', {
              "category": tags[i],
              "param": categoryParams?.elementAtOrNull(i),
            });
          } else if (itemType == 'search') {
            target = PageJumpTarget(_key!, 'search', {"keyword": tags[i]});
          } else if (itemType == 'search_with_namespace') {
            target = PageJumpTarget(_key!, 'search', {
              "keyword": "$name:$tags[i]",
            });
          } else {
            target = PageJumpTarget(_key!, itemType, null);
          }
          cs.add(CategoryItem(tags[i], target));
        }
        if (type == "fixed") {
          categoryParts.add(FixedCategoryPart(name, cs));
        } else if (type == "random") {
          categoryParts.add(
            RandomCategoryPart(name, cs, c["randomNumber"] ?? 1),
          );
        }
      }
    }

    return CategoryData(
      title: title,
      categories: categoryParts,
      enableRankingPage: enableRankingPage ?? false,
      key: title,
    );
  }

  CategoryComicsData? _loadCategoryComicsData() {
    if (!_checkExists("categoryComics")) return null;

    List<CategoryComicsOptions>? options;
    if (_checkExists("categoryComics.optionList")) {
      options = <CategoryComicsOptions>[];
      for (var element in _getValue("categoryComics.optionList") ?? []) {
        LinkedHashMap<String, String> map = LinkedHashMap<String, String>();
        for (var option in element["options"]) {
          if (option.isEmpty || !option.contains("-")) {
            continue;
          }
          var split = option.split("-");
          var key = split.removeAt(0);
          var value = split.join("-");
          map[key] = value;
        }
        options.add(
          CategoryComicsOptions(
            element["label"] ?? "",
            map,
            List.from(element["notShowWhen"] ?? []),
            element["showWhen"] == null ? null : List.from(element["showWhen"]),
          ),
        );
      }
    }

    CategoryOptionsLoader? optionLoader;
    if (_checkExists("categoryComics.optionLoader")) {
      optionLoader = (category, param) async {
        try {
          dynamic res = JsEngine().runCode("""
          ComicSource.sources.$_key.categoryComics.optionLoader(
            ${jsonEncode(category)}, ${jsonEncode(param)})
        """);
          if (res is Future) {
            res = await res;
          }
          if (res is! List) {
            return Res.error(
              "Invalid data:\nExpected: List\nGot: ${res.runtimeType}",
            );
          }
          var options = <CategoryComicsOptions>[];
          for (var element in res) {
            if (element is! Map) {
              return Res.error(
                "Invalid option data:\nExpected: Map\nGot: ${element.runtimeType}",
              );
            }
            LinkedHashMap<String, String> map = LinkedHashMap<String, String>();
            for (var option in element["options"] ?? []) {
              if (option.isEmpty || !option.contains("-")) {
                continue;
              }
              var split = option.split("-");
              var key = split.removeAt(0);
              var value = split.join("-");
              map[key] = value;
            }
            options.add(
              CategoryComicsOptions(
                element["label"] ?? "",
                map,
                List.from(element["notShowWhen"] ?? []),
                element["showWhen"] == null
                    ? null
                    : List.from(element["showWhen"]),
              ),
            );
          }
          return Res(options);
        } catch (e) {
          AppDiagnostics.error('source.data_analysis', e, message: 'category_options_load_failed');
          return Res.error(e.toString());
        }
      };
    }

    RankingData? rankingData;
    if (_checkExists("categoryComics.ranking")) {
      var options = <String, String>{};
      for (var option in _getValue("categoryComics.ranking.options")) {
        if (option.isEmpty || !option.contains("-")) {
          continue;
        }
        var split = option.split("-");
        var key = split.removeAt(0);
        var value = split.join("-");
        options[key] = value;
      }
      Future<Res<List<Comic>>> Function(String option, int page)? load;
      Future<Res<List<Comic>>> Function(String option, String? next)?
      loadWithNext;
      if (_checkExists("categoryComics.ranking.load")) {
        load = (option, page) async {
          try {
            var res = await JsEngine().runCode("""
            ComicSource.sources.$_key.categoryComics.ranking.load(
              ${jsonEncode(option)}, ${jsonEncode(page)})
          """);
            return Res(
              List.generate(
                res["comics"].length,
                (index) => Comic.fromJson(res["comics"][index], _key!),
              ),
              subData: res["maxPage"],
            );
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        };
      } else {
        loadWithNext = (option, next) async {
          try {
            var res = await JsEngine().runCode("""
            ComicSource.sources.$_key.categoryComics.ranking.loadWithNext(
              ${jsonEncode(option)}, ${jsonEncode(next)})
          """);
            return Res(
              List.generate(
                res["comics"].length,
                (index) => Comic.fromJson(res["comics"][index], _key!),
              ),
              subData: res["next"],
            );
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        };
      }
      rankingData = RankingData(options, load, loadWithNext);
    }

    if (options == null && optionLoader == null) {
      options = [];
    }

    return CategoryComicsData(
      options: options,
      optionsLoader: optionLoader,
      load: (category, param, options, page) async {
        try {
          var res = await JsEngine().runCode("""
              ComicSource.sources.$_key.categoryComics.load(
                ${jsonEncode(category)},
                ${jsonEncode(param)},
                ${jsonEncode(options)},
                ${jsonEncode(page)}
              )
            """);
          return Res(
            List.generate(
              res["comics"].length,
              (index) => Comic.fromJson(res["comics"][index], _key!),
            ),
            subData: res["maxPage"],
          );
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      },
      rankingData: rankingData,
    );
  }

  SearchPageData? _loadSearchData() {
    if (!_checkExists("search")) return null;
    var options = <SearchOptions>[];
    for (var element in _getValue("search.optionList") ?? []) {
      LinkedHashMap<String, String> map = LinkedHashMap<String, String>();
      for (var option in element["options"]) {
        if (option.isEmpty || !option.contains("-")) {
          continue;
        }
        var split = option.split("-");
        var key = split.removeAt(0);
        var value = split.join("-");
        map[key] = value;
      }
      options.add(
        SearchOptions(
          map,
          element["label"],
          element['type'] ?? 'select',
          element['default'] == null ? null : jsonEncode(element['default']),
        ),
      );
    }

    SearchFunction? loadPage;

    SearchNextFunction? loadNext;

    if (_checkExists('search.load')) {
      loadPage = (keyword, page, searchOption) async {
        try {
          var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.search.load(
            ${jsonEncode(keyword)}, ${jsonEncode(searchOption)}, ${jsonEncode(page)})
        """);
          return Res(
            List.generate(
              res["comics"].length,
              (index) => Comic.fromJson(res["comics"][index], _key!),
            ),
            subData: res["maxPage"],
          );
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      };
    } else {
      loadNext = (keyword, next, searchOption) async {
        try {
          var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.search.loadNext(
            ${jsonEncode(keyword)}, ${jsonEncode(searchOption)}, ${jsonEncode(next)})
        """);
          return Res(
            List.generate(
              res["comics"].length,
              (index) => Comic.fromJson(res["comics"][index], _key!),
            ),
            subData: res["next"],
          );
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      };
    }

    return SearchPageData(options, loadPage, loadNext);
  }

  LoadComicFunc? _parseLoadComicFunc() {
    return (id) async {
      try {
        var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.loadInfo(${jsonEncode(id)})
        """);
        if (res is! Map<String, dynamic>) throw "Invalid data";
        res['comicId'] = id;
        res['sourceKey'] = _key;
        return Res(ComicDetails.fromJson(res));
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  LoadComicPagesFunc? _parseLoadComicPagesFunc() {
    return (id, ep) async {
      try {
        var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.loadEp(${jsonEncode(id)}, ${jsonEncode(ep)})
        """);
        return Res(List.from(res["images"]));
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  FavoriteData? _loadFavoriteData() {
    if (!_checkExists("favorites")) return null;

    final bool multiFolder = _getValue("favorites.multiFolder");
    final bool? isOldToNewSort = _getValue("favorites.isOldToNewSort");
    final bool? singleFolderForSingleComic = _getValue(
      "favorites.singleFolderForSingleComic",
    );

    Future<Res<T>> retryZone<T>(Future<Res<T>> Function() func) async {
      if (!ComicSource.find(_key!)!.isLogged) {
        return const Res.error("Not login");
      }
      var res = await func();
      if (res.error && res.errorMessage!.contains("Login expired")) {
        var reLoginRes = await ComicSource.find(_key!)!.reLogin();
        if (!reLoginRes) {
          return const Res.error("Login expired and re-login failed");
        } else {
          return func();
        }
      }
      return res;
    }

    Future<Res<bool>> addOrDelFavFunc(
      String comicId,
      String folderId,
      bool isAdding,
      String? favId,
    ) async {
      func() async {
        try {
          await JsEngine().runCode("""
            ComicSource.sources.$_key.favorites.addOrDelFavorite(
              ${jsonEncode(comicId)}, ${jsonEncode(folderId)}, ${jsonEncode(isAdding)})
          """);
          return const Res(true);
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res<bool>.error(e.toString());
        }
      }

      return retryZone(func);
    }

    Future<Res<List<Comic>>> Function(int page, [String? folder])? loadComic;

    Future<Res<List<Comic>>> Function(String? next, [String? folder])? loadNext;

    if (_checkExists("favorites.loadComics")) {
      loadComic = (int page, [String? folder]) async {
        Future<Res<List<Comic>>> func() async {
          try {
            var res = await JsEngine().runCode("""
            ComicSource.sources.$_key.favorites.loadComics(
              ${jsonEncode(page)}, ${jsonEncode(folder)})
          """);
            return Res(
              List.generate(
                res["comics"].length,
                (index) => Comic.fromJson(res["comics"][index], _key!),
              ),
              subData: res["maxPage"],
            );
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        }

        return retryZone(func);
      };
    }

    if (_checkExists("favorites.loadNext")) {
      loadNext = (String? next, [String? folder]) async {
        Future<Res<List<Comic>>> func() async {
          try {
            var res = await JsEngine().runCode("""
            ComicSource.sources.$_key.favorites.loadNext(
              ${jsonEncode(next)}, ${jsonEncode(folder)})
          """);
            return Res(
              List.generate(
                res["comics"].length,
                (index) => Comic.fromJson(res["comics"][index], _key!),
              ),
              subData: res["next"],
            );
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        }

        return retryZone(func);
      };
    }

    Future<Res<Map<String, String>>> Function([String? comicId])? loadFolders;

    Future<Res<bool>> Function(String name)? addFolder;

    Future<Res<bool>> Function(String key)? deleteFolder;

    if (multiFolder) {
      loadFolders = ([String? comicId]) async {
        Future<Res<Map<String, String>>> func() async {
          try {
            var res = await JsEngine().runCode("""
            ComicSource.sources.$_key.favorites.loadFolders(${jsonEncode(comicId)})
          """);
            List<String>? subData;
            if (res["favorited"] != null) {
              subData = List.from(res["favorited"]);
            }
            return Res(Map.from(res["folders"]), subData: subData);
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        }

        return retryZone(func);
      };
      if (_checkExists("favorites.addFolder")) {
        addFolder = (name) async {
          try {
            await JsEngine().runCode("""
            ComicSource.sources.$_key.favorites.addFolder(${jsonEncode(name)})
          """);
            return const Res(true);
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        };
      }
      if (_checkExists("favorites.deleteFolder")) {
        deleteFolder = (key) async {
          try {
            await JsEngine().runCode("""
            ComicSource.sources.$_key.favorites.deleteFolder(${jsonEncode(key)})
          """);
            return const Res(true);
          } catch (e, s) {
            AppDiagnostics.error('source.network', e, stackTrace: s);
            return Res.error(e.toString());
          }
        };
      }
    }

    return FavoriteData(
      key: _key!,
      title: _name!,
      multiFolder: multiFolder,
      loadComic: loadComic,
      loadNext: loadNext,
      loadFolders: loadFolders,
      addFolder: addFolder,
      deleteFolder: deleteFolder,
      addOrDelFavorite: addOrDelFavFunc,
      isOldToNewSort: isOldToNewSort,
      singleFolderForSingleComic: singleFolderForSingleComic ?? false,
    );
  }

  CommentsLoader? _parseCommentsLoader() {
    if (!_checkExists("comic.loadComments")) return null;
    return (id, subId, page, replyTo) async {
      try {
        var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.loadComments(
            ${jsonEncode(id)}, ${jsonEncode(subId)}, ${jsonEncode(page)}, ${jsonEncode(replyTo)})
        """);
        return Res(
          (res["comments"] as List).map((e) => Comment.fromJson(e)).toList(),
          subData: res["maxPage"],
        );
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  SendCommentFunc? _parseSendCommentFunc() {
    if (!_checkExists("comic.sendComment")) return null;
    return (id, subId, content, replyTo) async {
      Future<Res<bool>> func() async {
        try {
          await JsEngine().runCode("""
            ComicSource.sources.$_key.comic.sendComment(
              ${jsonEncode(id)}, ${jsonEncode(subId)}, ${jsonEncode(content)}, ${jsonEncode(replyTo)})
          """);
          return const Res(true);
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      }

      var res = await func();
      if (res.error && res.errorMessage!.contains("Login expired")) {
        var reLoginRes = await ComicSource.find(_key!)!.reLogin();
        if (!reLoginRes) {
          return const Res.error("Login expired and re-login failed");
        } else {
          return func();
        }
      }
      return res;
    };
  }

  ChapterCommentsLoader? _parseChapterCommentsLoader() {
    if (!_checkExists("comic.loadChapterComments")) return null;
    return (comicId, epId, page, replyTo) async {
      try {
        var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.loadChapterComments(
            ${jsonEncode(comicId)}, ${jsonEncode(epId)}, ${jsonEncode(page)}, ${jsonEncode(replyTo)})
        """);
        return Res(
          (res["comments"] as List).map((e) => Comment.fromJson(e)).toList(),
          subData: res["maxPage"],
        );
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  SendChapterCommentFunc? _parseSendChapterCommentFunc() {
    if (!_checkExists("comic.sendChapterComment")) return null;
    return (comicId, epId, content, replyTo) async {
      Future<Res<bool>> func() async {
        try {
          await JsEngine().runCode("""
            ComicSource.sources.$_key.comic.sendChapterComment(
              ${jsonEncode(comicId)}, ${jsonEncode(epId)}, ${jsonEncode(content)}, ${jsonEncode(replyTo)})
          """);
          return const Res(true);
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      }

      var res = await func();
      if (res.error && res.errorMessage!.contains("Login expired")) {
        var reLoginRes = await ComicSource.find(_key!)!.reLogin();
        if (!reLoginRes) {
          return const Res.error("Login expired and re-login failed");
        } else {
          return func();
        }
      }
      return res;
    };
  }

  GetImageLoadingConfigFunc? _parseImageLoadingConfigFunc() {
    if (!_checkExists("comic.onImageLoad")) {
      return null;
    }
    return (imageKey, comicId, ep) async {
      var res = JsEngine().runCode("""
          ComicSource.sources.$_key.comic.onImageLoad(
            ${jsonEncode(imageKey)}, ${jsonEncode(comicId)}, ${jsonEncode(ep)})
        """);
      if (res is Future) {
        return await res;
      }
      return res;
    };
  }

  GetThumbnailLoadingConfigFunc? _parseThumbnailLoadingConfigFunc() {
    if (!_checkExists("comic.onThumbnailLoad")) {
      return null;
    }
    return (imageKey) {
      var res = JsEngine().runCode("""
          ComicSource.sources.$_key.comic.onThumbnailLoad(${jsonEncode(imageKey)})
        """);
      if (res is! Map) {
        AppDiagnostics.error('source.network', 'function onThumbnailLoad return invalid data', message: 'invalid_thumbnail_loader_result');
        throw "function onThumbnailLoad return invalid data";
      }
      return res as Map<String, dynamic>;
    };
  }

  ComicThumbnailLoader? _parseThumbnailLoader() {
    if (!_checkExists("comic.loadThumbnails")) {
      return null;
    }
    return (id, next) async {
      try {
        var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.loadThumbnails(${jsonEncode(id)}, ${jsonEncode(next)})
        """);
        return Res(
          List<String>.from(res[_jsonKeyThumbnails]),
          subData: res[_jsonKeyNext],
        );
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  LikeOrUnlikeComicFunc? _parseLikeFunc() {
    if (!_checkExists("comic.likeComic")) {
      return null;
    }
    return (id, isLiking) async {
      try {
        await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.likeComic(${jsonEncode(id)}, ${jsonEncode(isLiking)})
        """);
        return const Res(true);
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  VoteCommentFunc? _parseVoteCommentFunc() {
    if (!_checkExists("comic.voteComment")) {
      return null;
    }
    return (id, subId, commentId, isUp, isCancel) async {
      try {
        var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.voteComment(${jsonEncode(id)}, ${jsonEncode(subId)}, ${jsonEncode(commentId)}, ${jsonEncode(isUp)}, ${jsonEncode(isCancel)})
        """);
        return Res(res is num ? res.toInt() : 0);
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  LikeCommentFunc? _parseLikeCommentFunc() {
    if (!_checkExists("comic.likeComment")) {
      return null;
    }
    return (id, subId, commentId, isLiking) async {
      try {
        var res = await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.likeComment(${jsonEncode(id)}, ${jsonEncode(subId)}, ${jsonEncode(commentId)}, ${jsonEncode(isLiking)})
        """);
        return Res(res is num ? res.toInt() : 0);
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  Map<String, Map<String, dynamic>> _parseSettings() {
    var value = _getValue("settings");
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
    return {};
  }

  RegExp? _parseIdMatch() {
    if (!_checkExists("comic.idMatch")) {
      return null;
    }
    return RegExp(_getValue("comic.idMatch"));
  }

  Map<String, Map<String, String>>? _parseTranslation() {
    if (!_checkExists("translation")) {
      return null;
    }
    var data = _getValue("translation");
    var res = <String, Map<String, String>>{};
    for (var e in data.entries) {
      res[e.key] = Map<String, String>.from(e.value);
    }
    return res;
  }

  HandleClickTagEvent? _parseClickTagEvent() {
    if (!_checkExists("comic.onClickTag")) {
      return null;
    }
    return (namespace, tag) {
      var res = JsEngine().runCode("""
          ComicSource.sources.$_key.comic.onClickTag(${jsonEncode(namespace)}, ${jsonEncode(tag)})
        """);
      if (res is! Map) {
        return null;
      }
      var r = Map<String, dynamic>.from(res);
      r.removeWhere((key, value) => value == null);
      return PageJumpTarget.parse(_key!, r);
    };
  }

  TagSuggestionSelectFunc? _parseTagSuggestionSelectFunc() {
    if (!_checkExists("search.onTagSuggestionSelected")) {
      return null;
    }
    return (namespace, tag) {
      var res = JsEngine().runCode("""
          ComicSource.sources.$_key.search.onTagSuggestionSelected(
            ${jsonEncode(namespace)}, ${jsonEncode(tag)})
        """);
      return res is String ? res : "$namespace:$tag";
    };
  }

  LinkHandler? _parseLinkHandler() {
    if (!_checkExists("comic.link")) {
      return null;
    }
    List<String> domains = List.from(_getValue("comic.link.domains"));
    linkToId(String link) {
      var res = JsEngine().runCode("""
          ComicSource.sources.$_key.comic.link.linkToId(${jsonEncode(link)})
        """);
      return res as String?;
    }

    return LinkHandler(domains, linkToId);
  }

  StarRatingFunc? _parseStarRatingFunc() {
    if (!_checkExists("comic.starRating")) {
      return null;
    }
    return (id, rating) async {
      try {
        await JsEngine().runCode("""
          ComicSource.sources.$_key.comic.starRating(${jsonEncode(id)}, ${jsonEncode(rating)})
        """);
        return const Res(true);
      } catch (e, s) {
        AppDiagnostics.error('source.network', e, stackTrace: s);
        return Res.error(e.toString());
      }
    };
  }

  ArchiveDownloader? _parseArchiveDownloader() {
    if (!_checkExists("comic.archive")) {
      return null;
    }
    return ArchiveDownloader(
      (cid) async {
        try {
          var res = await JsEngine().runCode("""
              ComicSource.sources.$_key.comic.archive.getArchives(${jsonEncode(cid)})
            """);
          return Res(
            (res as List).map((e) => ArchiveInfo.fromJson(e)).toList(),
          );
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      },
      (cid, aid) async {
        try {
          var res = await JsEngine().runCode("""
              ComicSource.sources.$_key.comic.archive.getDownloadUrl(${jsonEncode(cid)}, ${jsonEncode(aid)})
            """);
          return Res(res as String);
        } catch (e, s) {
          AppDiagnostics.error('source.network', e, stackTrace: s);
          return Res.error(e.toString());
        }
      },
    );
  }
}
