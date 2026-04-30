import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/consts.dart';
import 'package:venera/foundation/debug_log_exporter.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/local_storage_legacy_bridge.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/utils/data.dart';
import 'package:venera/utils/data_sync.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';
import 'package:venera/foundation/adaptive/app_window_class.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yaml/yaml.dart';

part 'reader.dart';
part 'explore_settings.dart';
part 'setting_components.dart';
part 'appearance.dart';
part 'local_favorites.dart';
part 'app.dart';
part 'about.dart';
part 'network.dart';
part 'debug.dart';
part 'settings_schema.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialPage = -1, super.key});

  final int initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

int resolveSettingsPageIndex({
  required int currentPage,
  required int? initialPage,
  required int itemCount,
}) {
  bool isValidPage(int page) => page >= 0 && page < itemCount;

  if (isValidPage(currentPage)) {
    return currentPage;
  }
  if (initialPage != null && isValidPage(initialPage)) {
    return initialPage;
  }
  return 0;
}

class _SettingsPageState extends State<SettingsPage> {
  int currentPage = -1;

  ColorScheme get colors => Theme.of(context).colorScheme;

  bool get enableTwoViews =>
      classifyAppWidth(context.width) != AppWindowClass.compact;

  final categories = const <_SettingsCategoryItem>[
    _SettingsCategoryItem(title: "Explore", icon: Icons.explore),
    _SettingsCategoryItem(title: "Reading", icon: Icons.book),
    _SettingsCategoryItem(title: "Appearance", icon: Icons.color_lens),
    _SettingsCategoryItem(
      title: "Local Favorites",
      icon: Icons.collections_bookmark_rounded,
    ),
    _SettingsCategoryItem(title: "APP", icon: Icons.apps),
    _SettingsCategoryItem(title: "Network", icon: Icons.public),
    _SettingsCategoryItem(title: "About", icon: Icons.info),
    _SettingsCategoryItem(title: "Debug", icon: Icons.bug_report),
  ];

  @override
  void initState() {
    currentPage = widget.initialPage;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Material(child: buildBody());
  }

  Widget buildBody() {
    if (enableTwoViews) {
      final effectivePage = resolveSettingsPageIndex(
        currentPage: currentPage,
        initialPage: widget.initialPage,
        itemCount: categories.length,
      );
      return Row(
        children: [
          SizedBox(
            width: 280,
            height: double.infinity,
            child: buildLeft(selectedPage: effectivePage),
          ),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return LayoutBuilder(
                  builder: (context, constrains) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        var width = constrains.maxWidth;
                        var value = animation.isForwardOrCompleted
                            ? 1 - animation.value
                            : 1;
                        var left = width * value;
                        return Stack(
                          children: [
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: left,
                              width: width,
                              child: child,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
              child: buildRight(effectivePage),
            ),
          ),
        ],
      );
    } else {
      return buildLeft();
    }
  }

  Widget buildLeft({int? selectedPage}) {
    return Material(
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                if (!enableTwoViews) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: "Back",
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: context.pop,
                    ),
                  ),
                ],
                const SizedBox(width: 24),
                Text("Settings".tl, style: ts.s20),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: buildCategories(selectedPage: selectedPage)),
        ],
      ),
    );
  }

  Widget buildCategories({int? selectedPage}) {
    Widget buildItem(String name, int id) {
      final bool selected = id == (selectedPage ?? currentPage);

      Widget content = AnimatedContainer(
        key: ValueKey(id),
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 46,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        decoration: BoxDecoration(
          color: selected ? colors.primaryContainer.toOpacity(0.36) : null,
          border: Border(
            left: BorderSide(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(categories[id].icon),
            const SizedBox(width: 16),
            Text(name, style: ts.s16),
            const Spacer(),
            if (selected) const Icon(Icons.arrow_right),
          ],
        ),
      );

      return Padding(
        padding: enableTwoViews
            ? const EdgeInsets.fromLTRB(8, 0, 8, 0)
            : EdgeInsets.zero,
        child: InkWell(
          onTap: () {
            if (enableTwoViews) {
              setState(() => currentPage = id);
            } else {
              context.to(() => _SettingsDetailPage(pageIndex: id));
            }
          },
          child: content,
        ).paddingVertical(4),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: categories.length,
      itemBuilder: (context, index) =>
          buildItem(categories[index].title.tl, index),
    );
  }

  Widget buildRight(int pageIndex) {
    return Navigator(
      key: ValueKey(pageIndex),
      onGenerateRoute: (settings) {
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return _buildSettingsContent(pageIndex);
          },
          transitionDuration: Duration.zero,
        );
      },
    );
  }

  Widget _buildSettingsContent(int pageIndex) {
    return _settingsContentForIndex(pageIndex);
  }
}

class _SettingsCategoryItem {
  final String title;
  final IconData icon;

  const _SettingsCategoryItem({required this.title, required this.icon});
}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Material(child: _buildPage());
  }

  Widget _buildPage() {
    return _settingsContentForIndex(pageIndex);
  }
}

Widget _settingsContentForIndex(int pageIndex) {
  return switch (pageIndex) {
    0 => const ExploreSettings(),
    1 => const ReaderSettings(),
    2 => const AppearanceSettings(),
    3 => const LocalFavoritesSettings(),
    4 => const AppSettings(),
    5 => const NetworkSettings(),
    6 => const AboutSettings(),
    7 => const DebugPage(),
    _ => throw UnimplementedError(),
  };
}
