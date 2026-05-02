part of 'home_page.dart';

List<String> readLocalFavoriteFolderNames() {
  return LocalFavoritesManager().folderNames;
}

class _Local extends StatefulWidget {
  const _Local();

  @override
  State<_Local> createState() => _LocalState();
}

class _LocalState extends State<_Local> {
  final downloadQueue = const DownloadQueueRepository();
  List<LocalComic> local = const [];
  int count = 0;
  int downloadingTaskCount = 0;
  bool firstDownloadingTaskPaused = false;
  bool _isReady = false;
  bool _hasLegacyRuntimeData = false;

  ({List<LocalComic> recent, int count, int taskCount, bool firstTaskPaused})
  _readLocalSnapshot() {
    final tasks = downloadQueue.tasks;
    return (
      recent: legacyGetRecentLocalComics(),
      count: legacyCountLocalComics(),
      taskCount: tasks.length,
      firstTaskPaused: tasks.isNotEmpty && tasks.first.isPaused,
    );
  }

  void onLocalComicsChange() {
    if (!mounted) return;
    setState(_applyLocalSnapshot);
  }

  void _applyLocalSnapshot() {
    final snapshot = _readLocalSnapshot();
    local = snapshot.recent;
    count = snapshot.count;
    downloadingTaskCount = snapshot.taskCount;
    firstDownloadingTaskPaused = snapshot.firstTaskPaused;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    _hasLegacyRuntimeData = legacyIsLocalComicsInitialized();
    if (!mounted) {
      return;
    }
    if (_hasLegacyRuntimeData) {
      _applyLocalSnapshot();
      legacyAddLocalComicsListener(onLocalComicsChange);
      downloadQueue.addListener(onLocalComicsChange);
    }
    setState(() {
      _isReady = true;
    });
  }

  @override
  void dispose() {
    if (_isReady && _hasLegacyRuntimeData) {
      legacyRemoveLocalComicsListener(onLocalComicsChange);
      downloadQueue.removeListener(onLocalComicsChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            context.to(() => const LocalComicsPage());
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Center(child: Text('Local'.tl, style: ts.s18)),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(count.toString(), style: ts.s12),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_right),
                  ],
                ),
              ).paddingHorizontal(16),
              if (local.isNotEmpty)
                SizedBox(
                  height: 136,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: local.length,
                    itemBuilder: (context, index) {
                      final heroTag =
                          'home:local:${local[index].sourceKey}:${local[index].id}';
                      return SimpleComicTile(
                        comic: local[index],
                        heroTag: heroTag,
                        onTap: () {
                          context.to(
                            () => ComicPage(
                              id: local[index].id,
                              sourceKey: local[index].sourceKey,
                              cover: local[index].cover,
                              title: local[index].title,
                              heroTag: heroTag,
                            ),
                          );
                        },
                      ).paddingHorizontal(8).paddingVertical(2);
                    },
                  ),
                ).paddingHorizontal(8),
              Row(
                children: [
                  if (downloadingTaskCount > 0)
                    Button.outlined(
                      child: Row(
                        children: [
                          if (firstDownloadingTaskPaused)
                            const Icon(Icons.pause_circle_outline, size: 18)
                          else
                            const _AnimatedDownloadingIcon(),
                          const SizedBox(width: 8),
                          Text(
                            "@a Tasks".tlParams({'a': downloadingTaskCount}),
                          ),
                        ],
                      ),
                      onPressed: () {
                        showPopUpWidget(context, const DownloadingPage());
                      },
                    ),
                  const Spacer(),
                  Button.filled(onPressed: import, child: Text("Import".tl)),
                ],
              ).paddingHorizontal(16).paddingVertical(8),
            ],
          ),
        ),
      ),
    );
  }

  void import() {
    showDialog(
      barrierDismissible: false,
      context: App.rootContext,
      builder: (context) {
        return const _ImportComicsWidget();
      },
    );
  }
}
