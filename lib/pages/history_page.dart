import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/features/reader_next/bridge/approved_reader_next_navigation_executor.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/features/reader/data/reader_activity_repository.dart';
import 'package:venera/features/reader_next/bridge/history_route_cutover_controller.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/utils/translations.dart';

typedef ReaderNextHistoryOpenExecutorFactory =
    ReaderNextHistoryOpenExecutor Function();

ReaderNextHistoryOpenExecutor resolveHistoryReaderNextExecutor({
  ReaderNextHistoryOpenExecutor? injectedExecutor,
  ReaderNextHistoryOpenExecutorFactory? injectedFactory,
  ReaderNextHistoryOpenExecutorFactory approvedFactory =
      createApprovedHistoryReaderNextExecutor,
}) {
  return resolveApprovedReaderNextExecutor(
    injectedExecutor: injectedExecutor,
    injectedFactory: injectedFactory,
    approvedFactory: approvedFactory,
  );
}

Future<List<ReaderActivityItem>> loadHistoryPageActivity(
  ReaderActivityRepository repository,
) {
  return repository.loadAll();
}

Future<void> removeHistoryPageActivity(
  ReaderActivityRepository repository,
  String comicId,
) {
  return repository.remove(comicId);
}

Future<void> clearHistoryPageActivity(ReaderActivityRepository repository) {
  return repository.clear();
}

@visibleForTesting
ComicDetailProgressContext buildHistoryDetailProgressContextForTesting(
  ReaderActivityItem item,
) {
  return ComicDetailProgressContext(
    chapterId: item.chapterId,
    page: item.pageIndex > 0 ? item.pageIndex : 1,
    sourceRef: item.sourceRef,
  );
}

@visibleForTesting
Widget buildHistoryComicDetailRouteForTesting(
  ReaderActivityItem item, {
  String? heroTag,
}) {
  final progressContext = buildHistoryDetailProgressContextForTesting(item);
  if (isLocalSourceKey(item.sourceKey)) {
    return ComicDetailPage(
      comicId: item.id,
      title: item.title,
      cover: item.cover,
      heroTag: heroTag,
      progressContext: progressContext,
    );
  }
  return ComicPage(
    id: item.id,
    sourceKey: item.sourceKey,
    cover: item.cover,
    title: item.title,
    heroTag: heroTag,
    progressContext: progressContext,
  );
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.readerNextOpenExecutor,
    this.readerNextOpenExecutorFactory,
    this.onDiagnostic,
  });

  final ReaderNextHistoryOpenExecutor? readerNextOpenExecutor;
  final ReaderNextHistoryOpenExecutorFactory? readerNextOpenExecutorFactory;
  final HistoryDiagnosticSink? onDiagnostic;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final controller = FlyoutController();
  final HistoryRouteCutoverController _historyCutoverController =
      const HistoryRouteCutoverController();
  late final ReaderActivityRepository _repository;
  List<ReaderActivityItem> comics = const [];
  bool multiSelectMode = false;
  Map<ReaderActivityItem, bool> selectedComics = {};

  @override
  void initState() {
    super.initState();
    _repository = App.repositories.readerActivity;
    _refreshActivity();
  }

  Future<void> _refreshActivity() async {
    final nextComics = await loadHistoryPageActivity(_repository);
    if (!mounted) {
      return;
    }
    setState(() {
      comics = nextComics;
      if (multiSelectMode) {
        selectedComics.removeWhere((comic, _) => !comics.contains(comic));
        if (selectedComics.isEmpty) {
          multiSelectMode = false;
        }
      }
    });
  }

  void selectAll() {
    setState(() {
      selectedComics = comics.asMap().map((k, v) => MapEntry(v, true));
    });
  }

  void deSelect() {
    setState(() {
      selectedComics.clear();
    });
  }

  void invertSelection() {
    setState(() {
      comics.asMap().forEach((k, v) {
        selectedComics[v] = !selectedComics.putIfAbsent(v, () => false);
      });
      selectedComics.removeWhere((k, v) => !v);
    });
  }

  Future<void> _removeHistory(ReaderActivityItem comic) async {
    await removeHistoryPageActivity(_repository, comic.id);
    await _refreshActivity();
  }

  Future<void> _openHistoryComic(ReaderActivityItem comic) async {
    await App.rootContext.to(
      () => buildHistoryComicDetailRouteForTesting(comic),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> selectActions = [
      IconButton(
        icon: const Icon(Icons.select_all),
        tooltip: "Select All".tl,
        onPressed: selectAll,
      ),
      IconButton(
        icon: const Icon(Icons.deselect),
        tooltip: "Deselect".tl,
        onPressed: deSelect,
      ),
      IconButton(
        icon: const Icon(Icons.flip),
        tooltip: "Invert Selection".tl,
        onPressed: invertSelection,
      ),
      IconButton(
        icon: const Icon(Icons.delete),
        tooltip: "Delete".tl,
        onPressed: selectedComics.isEmpty
            ? null
            : () async {
                final comicsToDelete = List<ReaderActivityItem>.from(
                  selectedComics.keys,
                );
                setState(() {
                  multiSelectMode = false;
                  selectedComics.clear();
                });

                for (final comic in comicsToDelete) {
                  await removeHistoryPageActivity(_repository, comic.id);
                }
                await _refreshActivity();
              },
      ),
    ];

    List<Widget> normalActions = [
      IconButton(
        icon: const Icon(Icons.checklist),
        tooltip: multiSelectMode ? "Exit Multi-Select".tl : "Multi-Select".tl,
        onPressed: () {
          setState(() {
            multiSelectMode = !multiSelectMode;
          });
        },
      ),
      Tooltip(
        message: 'Clear History'.tl,
        child: Flyout(
          controller: controller,
          flyoutBuilder: (context) {
            return FlyoutContent(
              title: 'Clear History'.tl,
              content: Text('Are you sure you want to clear your history?'.tl),
              actions: [
                Button.filled(
                  color: context.colorScheme.error,
                  onPressed: () async {
                    await clearHistoryPageActivity(_repository);
                    context.pop();
                    await _refreshActivity();
                  },
                  child: Text('Clear'.tl),
                ),
              ],
            );
          },
          child: IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              controller.show();
            },
          ),
        ),
      ),
    ];

    return PopScope(
      canPop: !multiSelectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        }
      },
      child: Scaffold(
        body: SmoothCustomScrollView(
          slivers: [
            SliverAppbar(
              leading: Tooltip(
                message: multiSelectMode ? "Cancel".tl : "Back".tl,
                child: IconButton(
                  onPressed: () {
                    if (multiSelectMode) {
                      setState(() {
                        multiSelectMode = false;
                        selectedComics.clear();
                      });
                    } else {
                      context.pop();
                    }
                  },
                  icon: multiSelectMode
                      ? const Icon(Icons.close)
                      : const Icon(Icons.arrow_back),
                ),
              ),
              title: multiSelectMode
                  ? Text(selectedComics.length.toString())
                  : Text('History'.tl),
              actions: multiSelectMode ? selectActions : normalActions,
            ),
            SliverGridComics(
              comics: comics,
              selections: selectedComics,
              onLongPressed: null,
              onTap: multiSelectMode
                  ? (c, heroTag) {
                      final item = c as ReaderActivityItem;
                      setState(() {
                        if (selectedComics.containsKey(item)) {
                          selectedComics.remove(item);
                        } else {
                          selectedComics[item] = true;
                        }
                        if (selectedComics.isEmpty) {
                          multiSelectMode = false;
                        }
                      });
                    }
                  : (c, heroId) {
                      _openHistoryComic(c as ReaderActivityItem);
                    },
              badgeBuilder: (c) {
                if (isLocalSourceKey(c.sourceKey)) {
                  return 'Local'.tl;
                }
                return ComicSource.find(c.sourceKey)?.name ?? c.sourceKey;
              },
              menuBuilder: (c) {
                return [
                  MenuEntry(
                    icon: Icons.remove,
                    text: 'Remove'.tl,
                    color: context.colorScheme.error,
                    onClick: () async {
                      await _removeHistory(c as ReaderActivityItem);
                    },
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}
