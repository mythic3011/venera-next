part of 'comic_page.dart';

String _chapterWidgetIdentity({
  required String sourceKey,
  required String comicId,
}) => '$sourceKey:$comicId';

@visibleForTesting
bool updateChapterShowAllForDependencyForTesting({
  required bool currentShowAll,
  required bool isLocalSource,
  required String? previousIdentity,
  required String nextIdentity,
}) {
  if (!isLocalSource) {
    return currentShowAll;
  }
  if (previousIdentity != nextIdentity) {
    return true;
  }
  return currentShowAll;
}

class GroupedChapterSelection {
  const GroupedChapterSelection({
    required this.displayIndex,
    required this.sourceIndex,
    required this.chapterIndex,
    required this.rawIndex,
    required this.groupedIndex,
  });

  final int displayIndex;
  final int sourceIndex;
  final int chapterIndex;
  final String rawIndex;
  final String groupedIndex;
}

@visibleForTesting
GroupedChapterSelection resolveGroupedChapterSelectionForTesting({
  required List<int> groupLengths,
  required int groupIndex,
  required int displayIndex,
  required bool reverse,
}) {
  final groupLength = groupLengths[groupIndex];
  final sourceIndex = reverse
      ? groupLength - displayIndex - 1
      : displayIndex;
  var chapterIndex = sourceIndex;
  for (var i = 0; i < groupIndex; i++) {
    chapterIndex += groupLengths[i];
  }
  return GroupedChapterSelection(
    displayIndex: displayIndex,
    sourceIndex: sourceIndex,
    chapterIndex: chapterIndex,
    rawIndex: (chapterIndex + 1).toString(),
    groupedIndex: '${groupIndex + 1}-${sourceIndex + 1}',
  );
}

@visibleForTesting
TabController syncGroupedChapterTabControllerForTesting({
  required TabController? current,
  required int requestedIndex,
  required int length,
  required TickerProvider vsync,
  required VoidCallback listener,
}) {
  final clampedIndex = length == 0 ? 0 : requestedIndex.clamp(0, length - 1);
  if (current != null && current.length == length) {
    if (current.index != clampedIndex) {
      current.index = clampedIndex;
    }
    return current;
  }
  current?.removeListener(listener);
  current?.dispose();
  final controller = TabController(
    initialIndex: clampedIndex,
    length: length,
    vsync: vsync,
  );
  controller.addListener(listener);
  return controller;
}

bool comicChapterIsVisited(
  History? history, {
  required String rawIndex,
  String? groupedIndex,
}) {
  if (history == null) {
    return false;
  }
  return history.readEpisode.contains(rawIndex) ||
      (groupedIndex != null && history.readEpisode.contains(groupedIndex));
}

class _ComicChapters extends StatelessWidget {
  const _ComicChapters({this.history, required this.groupedMode});

  final History? history;

  final bool groupedMode;

  @override
  Widget build(BuildContext context) {
    return groupedMode
        ? _GroupedComicChapters(history)
        : _NormalComicChapters(history);
  }
}

class _NormalComicChapters extends StatefulWidget {
  const _NormalComicChapters(this.history);

  final History? history;

  @override
  State<_NormalComicChapters> createState() => _NormalComicChaptersState();
}

class _NormalComicChaptersState extends State<_NormalComicChapters> {
  late _ComicPageState state;

  late bool reverse;

  bool showAll = false;

  late History? history;

  late ComicChapters chapters;
  String? _comicIdentity;

  @override
  void initState() {
    super.initState();
    reverse = appdata.settings["reverseChapterOrder"] ?? false;
    history = widget.history;
  }

  @override
  void didChangeDependencies() {
    state = context.findAncestorStateOfType<_ComicPageState>()!;
    chapters = state.comic.chapters!;
    final nextIdentity = _chapterWidgetIdentity(
      sourceKey: state.comic.sourceKey,
      comicId: state.widget.id,
    );
    showAll = updateChapterShowAllForDependencyForTesting(
      currentShowAll: showAll,
      isLocalSource: isLocalSourceKey(state.comic.sourceKey),
      previousIdentity: _comicIdentity,
      nextIdentity: nextIdentity,
    );
    _comicIdentity = nextIdentity;
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant _NormalComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    history = widget.history;
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        int length = chapters.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == chapters.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: ListTile(
                title: Text("Chapters".tl),
                trailing: Tooltip(
                  message: "Order".tl,
                  child: IconButton(
                    icon: Icon(
                      reverse
                          ? Icons.vertical_align_top
                          : Icons.vertical_align_bottom_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        reverse = !reverse;
                      });
                    },
                  ),
                ),
              ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(childCount: length, (
                context,
                i,
              ) {
                if (reverse) {
                  i = chapters.length - i - 1;
                }
                var key = chapters.ids.elementAt(i);
                var value = chapters[key]!;
                final visited = comicChapterIsVisited(
                  history,
                  rawIndex: (i + 1).toString(),
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: context.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => state.read(i + 1),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Text(
                            value,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: visited
                                  ? context.colorScheme.outline
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 8)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${chapters.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(child: Divider()),
          ],
        );
      },
    );
  }
}

class _GroupedComicChapters extends StatefulWidget {
  const _GroupedComicChapters(this.history);

  final History? history;

  @override
  State<_GroupedComicChapters> createState() => _GroupedComicChaptersState();
}

class _GroupedComicChaptersState extends State<_GroupedComicChapters>
    with SingleTickerProviderStateMixin {
  late _ComicPageState state;

  late bool reverse;

  bool showAll = false;

  late History? history;

  late ComicChapters chapters;

  TabController? tabController;

  late int index;
  String? _comicIdentity;

  @override
  void initState() {
    super.initState();
    reverse = appdata.settings["reverseChapterOrder"] ?? false;
    history = widget.history;
    if (history?.group != null) {
      index = history!.group! - 1;
    } else {
      index = 0;
    }
  }

  @override
  void didChangeDependencies() {
    state = context.findAncestorStateOfType<_ComicPageState>()!;
    chapters = state.comic.chapters!;
    final nextIdentity = _chapterWidgetIdentity(
      sourceKey: state.comic.sourceKey,
      comicId: state.widget.id,
    );
    showAll = updateChapterShowAllForDependencyForTesting(
      currentShowAll: showAll,
      isLocalSource: isLocalSourceKey(state.comic.sourceKey),
      previousIdentity: _comicIdentity,
      nextIdentity: nextIdentity,
    );
    _comicIdentity = nextIdentity;
    tabController = syncGroupedChapterTabControllerForTesting(
      current: tabController,
      requestedIndex: index,
      length: chapters.groups.length,
      vsync: this,
      listener: onTabChange,
    );
    super.didChangeDependencies();
  }

  void onTabChange() {
    if (index != tabController!.index) {
      setState(() {
        index = tabController!.index;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _GroupedComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    history = widget.history;
  }

  @override
  void dispose() {
    tabController?.removeListener(onTabChange);
    tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        var group = chapters.getGroupByIndex(index);
        int length = group.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == group.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: ListTile(
                title: Text("Chapters".tl),
                trailing: Tooltip(
                  message: "Order".tl,
                  child: IconButton(
                    icon: Icon(
                      reverse
                          ? Icons.vertical_align_top
                          : Icons.vertical_align_bottom_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        reverse = !reverse;
                      });
                    },
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AppTabBar(
                withUnderLine: false,
                controller: tabController!,
                tabs: chapters.groups.map((e) => Tab(text: e)).toList(),
              ),
            ),
            SliverPadding(padding: const EdgeInsets.only(top: 8)),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(childCount: length, (
                context,
                i,
              ) {
                final selection = resolveGroupedChapterSelectionForTesting(
                  groupLengths: [
                    for (var j = 0; j < chapters.groupCount; j++)
                      chapters.getGroupByIndex(j).length,
                  ],
                  groupIndex: index,
                  displayIndex: i,
                  reverse: reverse,
                );
                var key = group.keys.elementAt(selection.sourceIndex);
                var value = group[key]!;
                final visited = comicChapterIsVisited(
                  history,
                  rawIndex: selection.rawIndex,
                  groupedIndex: selection.groupedIndex,
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: context.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => state.read(selection.chapterIndex + 1),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Text(
                            value,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: visited
                                  ? context.colorScheme.outline
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 8)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${group.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(child: Divider()),
          ],
        );
      },
    );
  }
}
