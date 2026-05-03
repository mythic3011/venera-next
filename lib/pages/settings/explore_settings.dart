part of 'settings_page.dart';

enum _AutoLanguageFilter {
  none('none', "None"),
  chinese('chinese', "Chinese"),
  english('english', "English"),
  japanese('japanese', "Japanese");

  final String value;
  final String label;
  const _AutoLanguageFilter(this.value, this.label);
}

enum _InitialPageTarget {
  home('0', "Home Page"),
  favorites('1', "Favorites Page"),
  explore('2', "Explore Page"),
  categories('3', "Categories Page");

  final String value;
  final String label;
  const _InitialPageTarget(this.value, this.label);
}

class ExploreSettings extends StatefulWidget {
  const ExploreSettings({super.key});

  @override
  State<ExploreSettings> createState() => _ExploreSettingsState();
}

class _ExploreSettingsState extends State<ExploreSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Explore".tl)),
        SelectSetting(
          title: "Display mode of comic tile".tl,
          settingKey: ExploreSettingKeys.comicDisplayMode.name,
          optionTranslation: {"detailed": "Detailed".tl, "brief": "Brief".tl},
        ).toSliver(),
        _SliderSetting(
          title: "Size of comic tile".tl,
          settingsIndex: ExploreSettingKeys.comicTileScale.name,
          interval: 0.05,
          min: 0.5,
          max: 1.5,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Explore Pages".tl,
          builder: setExplorePagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Category Pages".tl,
          builder: setCategoryPagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Network Favorite Pages".tl,
          builder: setFavoritesPagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Search Sources".tl,
          builder: setSearchSourcesWidget,
        ).toSliver(),
        _SwitchSetting(
          title: "Show favorite status on comic tile".tl,
          settingKey: ExploreSettingKeys.showFavoriteStatusOnTile.name,
        ).toSliver(),
        _SwitchSetting(
          title: "Show history on comic tile".tl,
          settingKey: ExploreSettingKeys.showHistoryStatusOnTile.name,
        ).toSliver(),
        _SwitchSetting(
          title: "Reverse default chapter order".tl,
          settingKey: ExploreSettingKeys.reverseChapterOrder.name,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Keyword blocking".tl,
          builder: () => const _ManageBlockingWordView(),
        ).toSliver(),
        _PopupWindowSetting(
          title: "Comment keyword blocking".tl,
          builder: () => const _ManageBlockingCommentWordView(),
        ).toSliver(),
        SelectSetting(
          title: "Default Search Target".tl,
          settingKey: ExploreSettingKeys.defaultSearchTarget.name,
          optionTranslation: {
            aggregatedSearchSourceKey: "Aggregated".tl,
            ...(() {
              var map = <String, String>{};
              for (var c in ComicSource.all()) {
                map[c.key] = c.name;
              }
              return map;
            }()),
          },
        ).toSliver(),
        SelectSetting(
          title: "Auto Language Filters".tl,
          settingKey: ExploreSettingKeys.autoAddLanguageFilter.name,
          optionTranslation: {
            for (final f in _AutoLanguageFilter.values) f.value: f.label.tl,
          },
        ).toSliver(),
        SelectSetting(
          title: "Initial Page".tl,
          settingKey: ExploreSettingKeys.initialPage.name,
          optionTranslation: {
            for (final p in _InitialPageTarget.values) p.value: p.label.tl,
          },
        ).toSliver(),
        SelectSetting(
          title: "Display mode of comic list".tl,
          settingKey: ExploreSettingKeys.comicListDisplayMode.name,
          optionTranslation: {
            "paging": "Paging".tl,
            "Continuous": "Continuous".tl,
          },
        ).toSliver(),
      ],
    );
  }
}

class _ManageBlockingWordView extends StatefulWidget {
  const _ManageBlockingWordView();

  @override
  State<_ManageBlockingWordView> createState() =>
      _ManageBlockingWordViewState();
}

class _ManageBlockingWordViewState extends State<_ManageBlockingWordView> {
  @override
  Widget build(BuildContext context) {
    assert(appdata.settings["blockedWords"] is List);
    assert(appdata.settings[ExploreSettingKeys.blockedWords.name] is List);
    return PopUpWidgetScaffold(
      title: "Keyword blocking".tl,
      tailing: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text("Add".tl),
          onPressed: add,
        ),
      ],
      body: ListView.builder(
        itemCount:
            appdata.settings[ExploreSettingKeys.blockedWords.name].length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(
              appdata.settings[ExploreSettingKeys.blockedWords.name][index],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                appdata.settings[ExploreSettingKeys.blockedWords.name].removeAt(
                  index,
                );
                appdata.saveData();
                setState(() {});
              },
            ),
          );
        },
      ),
    );
  }

  void add() {
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        var controller = TextEditingController();
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Add keyword".tl,
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  label: Text("Keyword".tl),
                  errorText: error,
                ),
                onChanged: (s) {
                  if (error != null) {
                    setState(() {
                      error = null;
                    });
                  }
                },
              ).paddingHorizontal(12),
              actions: [
                Button.filled(
                  onPressed: () {
                    if (appdata.settings[ExploreSettingKeys.blockedWords.name]
                        .contains(controller.text)) {
                      setState(() {
                        error = "Keyword already exists".tl;
                      });
                      return;
                    }
                    appdata.settings[ExploreSettingKeys.blockedWords.name].add(
                      controller.text,
                    );
                    appdata.saveData();
                    this.setState(() {});
                    context.pop();
                  },
                  child: Text("Add".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

Widget setExplorePagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    for (var page in c.explorePages) {
      pages[page.title] = page.title.ts(c.key);
    }
  }
  return _MultiPagesFilter(
    title: "Explore Pages".tl,
    settingsIndex: ExploreSettingKeys.explorePages.name,
    pages: pages,
  );
}

Widget setCategoryPagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    if (c.categoryData != null) {
      pages[c.categoryData!.key] = c.categoryData!.title;
    }
  }
  return _MultiPagesFilter(
    title: "Category Pages".tl,
    settingsIndex: ExploreSettingKeys.categories.name,
    pages: pages,
  );
}

Widget setFavoritesPagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    if (c.favoriteData != null) {
      pages[c.favoriteData!.key] = c.favoriteData!.title;
    }
  }
  return _MultiPagesFilter(
    title: "Network Favorite Pages".tl,
    settingsIndex: ExploreSettingKeys.favorites.name,
    pages: pages,
  );
}

Widget setSearchSourcesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.all()) {
    if (c.searchPageData != null) {
      pages[c.key] = c.name;
    }
  }
  return _MultiPagesFilter(
    title: "Search Sources".tl,
    settingsIndex: ExploreSettingKeys.searchSources.name,
    pages: pages,
  );
}

class _ManageBlockingCommentWordView extends StatefulWidget {
  const _ManageBlockingCommentWordView();

  @override
  State<_ManageBlockingCommentWordView> createState() =>
      _ManageBlockingCommentWordViewState();
}

class _ManageBlockingCommentWordViewState
    extends State<_ManageBlockingCommentWordView> {
  @override
  Widget build(BuildContext context) {
    assert(appdata.settings["blockedCommentWords"] is List);
    return PopUpWidgetScaffold(
      title: "Comment keyword blocking".tl,
      tailing: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text("Add".tl),
          onPressed: add,
        ),
      ],
      body: ListView.builder(
        itemCount: appdata.settings["blockedCommentWords"].length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(appdata.settings["blockedCommentWords"][index]),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                appdata.settings["blockedCommentWords"].removeAt(index);
                appdata.saveData();
                setState(() {});
              },
            ),
          );
        },
      ),
    );
  }

  void add() {
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        var controller = TextEditingController();
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Add keyword".tl,
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  label: Text("Keyword".tl),
                  errorText: error,
                ),
                onChanged: (s) {
                  if (error != null) {
                    setState(() {
                      error = null;
                    });
                  }
                },
              ).paddingHorizontal(12),
              actions: [
                Button.filled(
                  onPressed: () {
                    if (appdata.settings["blockedCommentWords"].contains(
                      controller.text,
                    )) {
                      setState(() {
                        error = "Keyword already exists".tl;
                      });
                      return;
                    }
                    appdata.settings["blockedCommentWords"].add(
                      controller.text,
                    );
                    appdata.saveData();
                    this.setState(() {});
                    context.pop();
                  },
                  child: Text("Add".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
