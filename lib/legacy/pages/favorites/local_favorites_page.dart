part of 'favorites_page.dart';

const _localAllFolderLabel = '^_^[%local_all%]^_^';

/// If the number of comics in a folder exceeds this limit, it will be
/// fetched asynchronously.
const _asyncDataFetchLimit = 500;

class _LocalFavoritesPage extends StatefulWidget {
  const _LocalFavoritesPage({required this.folder, super.key});

  final String folder;

  @override
  State<_LocalFavoritesPage> createState() => _LocalFavoritesPageState();
}

String readLocalFavoritesReadFilterPreference(String fallback) {
  recordAppdataAuthorityDiagnostic(
    channel: 'appdata.audit',
    event: 'appdata.authority.access',
    key: 'local_favorites_read_filter',
    storage: AppdataAuditStorage.implicitData,
    access: 'read',
    data: const <String, Object?>{'owner': 'LocalFavoritesPage'},
  );
  return (appdata.implicitData['local_favorites_read_filter'] ?? fallback)
      .toString();
}

int readLocalFavoritesUpdatePageNumPreference(int fallback) {
  recordAppdataAuthorityDiagnostic(
    channel: 'appdata.audit',
    event: 'appdata.authority.access',
    key: 'local_favorites_update_page_num',
    storage: AppdataAuditStorage.implicitData,
    access: 'read',
    data: const <String, Object?>{'owner': 'LocalFavoritesPage'},
  );
  final raw = appdata.implicitData['local_favorites_update_page_num'];
  if (raw is int) {
    return raw;
  }
  return fallback;
}

class _LocalFavoritesPageState extends State<_LocalFavoritesPage> {
  late _FavoritesPageState favPage;

  late List<FavoriteItem> comics;

  String? networkSource;
  String? networkFolder;

  Map<Comic, bool> selectedComics = {};

  var selectedLocalFolders = <String>{};

  late List<String> added = [];

  String keyword = "";
  bool searchHasUpper = false;

  bool searchMode = false;

  bool multiSelectMode = false;

  int? lastSelectedIndex;

  bool get isAllFolder => widget.folder == _localAllFolderLabel;

  bool isLoading = false;

  late String readFilterSelect;

  var searchResults = <FavoriteItem>[];
  Map<String, ReaderComicStatus> _statuses =
      const <String, ReaderComicStatus>{};
  int _statusRequestId = 0;
  final FavoritesRouteCutoverController _favoritesCutoverController =
      const FavoritesRouteCutoverController();

  ReadinessArtifact _currentReadinessArtifact() {
    return const ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: false,
      allowFavorites: false,
      allowDownloads: false,
    );
  }

  Future<void> _openFavoriteComic(FavoriteItem comic) async {
    final readerNextEnabled = isFavoritesReaderNextFlagEnabled(
      appdata.settings['reader_next_enabled'],
    );
    final readerNextFavoritesEnabled = isFavoritesReaderNextFlagEnabled(
      appdata.settings['reader_next_favorites_enabled'],
    );
    final input = IdentityCoverageInput.favorite(
      recordId: comic.id,
      sourceKey: comic.sourceKey,
      folderName: widget.folder,
      canonicalComicId: null,
      sourceRef: null,
      explicitSnapshotAlreadyPersisted: false,
    );
    await routeFavoritesReadOpen(
      controller: _favoritesCutoverController,
      input: input,
      artifact: _currentReadinessArtifact(),
      isRowStale: false,
      readerNextEnabled: readerNextEnabled,
      readerNextFavoritesEnabled: readerNextFavoritesEnabled,
      openLegacy: () async {
        await const ReaderRouteDispatchAuthority().openLegacy(
          ReaderOpenRequest(
            comicId: comic.id,
            sourceKey: comic.sourceKey,
            diagnosticEntrypoint: 'local_favorites.item',
            diagnosticCaller: '_LocalFavoritesPageState._openFavoriteComic',
          ),
        );
      },
      openReaderNext: (request) async {
        await const ReaderRouteDispatchAuthority().openApprovedReaderNext(
          request: request,
          injectedExecutor: favPage.widget.readerNextOpenExecutor,
          injectedFactory: favPage.widget.readerNextOpenExecutorFactory,
        );
        context.showMessage(message: 'ReaderNext open dispatched'.tl);
      },
      onBlocked: (result) async {
        context.showMessage(
          message: 'ReaderNext blocked (${result.diagnostic.blockedReason})'.tl,
        );
      },
      onDiagnostic: (packet) {
        favPage.widget.onDiagnostic?.call(packet);
        AppDiagnostics.info(
          'reader.preflight',
          'favorites_reader_next_preflight',
          data: {
            'routeDecision': packet.routeDecision.name,
            'recordKind': packet.recordKind,
            'folderName': packet.folderName,
            'recordId': packet.recordIdRedacted,
            'sourceKey': packet.sourceKey,
            'validation': packet.currentSourceRefValidationCode,
            'schema': packet.readinessArtifactSchemaVersion,
            'blockedReason': packet.blockedReason,
          },
        );
      },
    );
  }

  void updateSearchResult() {
    setState(() {
      if (keyword.trim().isEmpty) {
        searchResults = comics;
      } else {
        searchResults = [];
        for (var comic in comics) {
          if (matchKeyword(keyword, comic) ||
              matchKeywordT(keyword, comic) ||
              matchKeywordS(keyword, comic)) {
            searchResults.add(comic);
          }
        }
      }
    });
  }

  void updateComics() {
    if (isLoading) return;
    if (isAllFolder) {
      var totalComics = favoritesRepo.totalComics;
      if (totalComics < _asyncDataFetchLimit) {
        comics = favoritesRepo.getAllComics();
        unawaited(_loadStatuses(comics));
      } else {
        isLoading = true;
        favoritesRepo
            .getAllComicsAsync()
            .minTime(const Duration(milliseconds: 200))
            .then((value) {
              if (mounted) {
                setState(() {
                  isLoading = false;
                  comics = value;
                });
                unawaited(_loadStatuses(value));
              }
            });
      }
    } else {
      var folderComics = favoritesRepo.folderComics(widget.folder);
      if (folderComics < _asyncDataFetchLimit) {
        comics = favoritesRepo.getFolderComics(widget.folder);
        unawaited(_loadStatuses(comics));
      } else {
        isLoading = true;
        favoritesRepo
            .getFolderComicsAsync(widget.folder)
            .minTime(const Duration(milliseconds: 200))
            .then((value) {
              if (mounted) {
                setState(() {
                  isLoading = false;
                  comics = value;
                });
                unawaited(_loadStatuses(value));
              }
            });
      }
    }
    setState(() {});
  }

  Future<void> _syncNetworkFolder(int updatePageNum) async {
    await importNetworkFolder(
      context,
      networkSource!,
      updatePageNum,
      widget.folder,
      networkFolder!,
    );
    if (!mounted) {
      return;
    }
    updateComics();
  }

  Future<void> _loadStatuses(List<FavoriteItem> target) async {
    final requestId = ++_statusRequestId;
    if (target.isEmpty) {
      if (!mounted || requestId != _statusRequestId) {
        return;
      }
      setState(() {
        _statuses = const <String, ReaderComicStatus>{};
      });
      return;
    }
    try {
      final statuses = await App.repositories.readerStatus
          .loadStatusesForComics(target);
      if (!mounted || requestId != _statusRequestId) {
        return;
      }
      setState(() {
        _statuses = statuses;
      });
    } catch (_) {
      if (!mounted || requestId != _statusRequestId) {
        return;
      }
      setState(() {
        _statuses = const <String, ReaderComicStatus>{};
      });
    }
  }

  List<FavoriteItem> filterComics(List<FavoriteItem> curComics) {
    return curComics.where((comic) {
      final status =
          _statuses[readerStatusMapKey(
            comicId: comic.id,
            sourceKey: comic.sourceKey,
          )];
      final pageIndex = status?.pageIndex;
      final maxPage = status?.maxPage;
      final isCompleted =
          pageIndex != null &&
          maxPage != null &&
          maxPage > 0 &&
          pageIndex >= maxPage;
      if (readFilterSelect == "UnCompleted") {
        return !isCompleted;
      } else if (readFilterSelect == "Completed") {
        return isCompleted;
      }
      return true;
    }).toList();
  }

  bool matchKeyword(String keyword, FavoriteItem comic) {
    var list = keyword.split(" ");
    for (var k in list) {
      if (k.isEmpty) continue;
      if (checkKeyWordMatch(k, comic.title, false)) {
        continue;
      } else if (comic.subtitle != null &&
          checkKeyWordMatch(k, comic.subtitle!, false)) {
        continue;
      } else if (comic.tags.any((tag) {
        if (checkKeyWordMatch(k, tag, true)) {
          return true;
        } else if (tag.contains(':') &&
            checkKeyWordMatch(k, tag.split(':')[1], true)) {
          return true;
        } else if (App.locale.languageCode != 'en' &&
            checkKeyWordMatch(k, tag.translateTagsToCN, true)) {
          return true;
        }
        return false;
      })) {
        continue;
      } else if (checkKeyWordMatch(k, comic.author, true)) {
        continue;
      }
      return false;
    }
    return true;
  }

  bool checkKeyWordMatch(String keyword, String compare, bool needEqual) {
    String temp = compare;
    // 没有大写的话, 就转成小写比较, 避免搜索需要注意大小写
    if (!searchHasUpper) {
      temp = temp.toLowerCase();
    }
    if (needEqual) {
      return keyword == temp;
    }
    return temp.contains(keyword);
  }

  // Convert keyword to traditional Chinese to match comics
  bool matchKeywordT(String keyword, FavoriteItem comic) {
    if (!OpenCC.hasChineseSimplified(keyword)) {
      return false;
    }
    keyword = OpenCC.simplifiedToTraditional(keyword);
    return matchKeyword(keyword, comic);
  }

  // Convert keyword to simplified Chinese to match comics
  bool matchKeywordS(String keyword, FavoriteItem comic) {
    if (!OpenCC.hasChineseTraditional(keyword)) {
      return false;
    }
    keyword = OpenCC.traditionalToSimplified(keyword);
    return matchKeyword(keyword, comic);
  }

  @override
  void initState() {
    readFilterSelect = readLocalFavoritesReadFilterPreference(
      readFilterList[0],
    );
    favPage = context.findAncestorStateOfType<_FavoritesPageState>()!;
    if (!isAllFolder) {
      var (a, b) = favoritesRepo.findLinked(widget.folder);
      networkSource = a;
      networkFolder = b;
    } else {
      networkSource = null;
      networkFolder = null;
    }
    comics = [];
    updateComics();
    favoritesRepo.addListener(updateComics);
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    favoritesRepo.removeListener(updateComics);
  }

  void selectAll() {
    setState(() {
      if (searchMode) {
        selectedComics = searchResults.asMap().map((k, v) => MapEntry(v, true));
      } else {
        selectedComics = comics.asMap().map((k, v) => MapEntry(v, true));
      }
    });
  }

  void invertSelection() {
    setState(() {
      if (searchMode) {
        for (var c in searchResults) {
          if (selectedComics.containsKey(c)) {
            selectedComics.remove(c);
          } else {
            selectedComics[c] = true;
          }
        }
      } else {
        for (var c in comics) {
          if (selectedComics.containsKey(c)) {
            selectedComics.remove(c);
          } else {
            selectedComics[c] = true;
          }
        }
      }
    });
  }

  Future<bool> downloadComic(FavoriteItem c) async {
    var source = c.type.comicSource;
    if (source != null) {
      final canonicalComicId = canonicalComicIdForStatus(
        comicId: c.id,
        sourceKey: c.sourceKey,
      );
      final isDownloaded =
          await App.repositories.localLibrary.loadPrimaryLocalLibraryItem(
            canonicalComicId,
          ) !=
          null;
      if (isDownloaded) {
        return false;
      }
      legacyAddDownloadQueueTask(
        ImagesDownloadTask(source: source, comicId: c.id, comicTitle: c.title),
      );
      return true;
    }
    return false;
  }

  Future<void> downloadSelected() async {
    int count = 0;
    for (var c in selectedComics.keys) {
      if (await downloadComic(c as FavoriteItem)) {
        count++;
      }
    }
    if (count > 0) {
      context.showMessage(
        message: "Added @c comics to download queue.".tlParams({"c": count}),
      );
    }
  }

  var scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    var title = favPage.folder ?? "Unselected".tl;
    if (title == _localAllFolderLabel) {
      title = "All".tl;
    }

    Widget body = SmoothCustomScrollView(
      controller: scrollController,
      slivers: [
        if (!searchMode && !multiSelectMode)
          SliverAppbar(
            style: context.width < changePoint
                ? AppbarStyle.shadow
                : AppbarStyle.blur,
            leading: Tooltip(
              message: "Folders".tl,
              child: context.width <= _kTwoPanelChangeWidth
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      color: context.colorScheme.primary,
                      onPressed: favPage.showFolderSelector,
                    )
                  : const SizedBox(),
            ),
            title: GestureDetector(
              onTap: context.width < _kTwoPanelChangeWidth
                  ? favPage.showFolderSelector
                  : null,
              child: Text(title),
            ),
            actions: [
              if (networkSource != null && !isAllFolder)
                Tooltip(
                  message: "Sync".tl,
                  child: Flyout(
                    flyoutBuilder: (context) {
                      final GlobalKey<_SelectUpdatePageNumState>
                      selectUpdatePageNumKey =
                          GlobalKey<_SelectUpdatePageNumState>();
                      var updatePageWidget = _SelectUpdatePageNum(
                        networkSource: networkSource!,
                        networkFolder: networkFolder,
                        key: selectUpdatePageNumKey,
                      );
                      return FlyoutContent(
                        title: "Sync".tl,
                        content: updatePageWidget,
                        actions: [
                          Button.filled(
                            child: Text("Update".tl),
                            onPressed: () async {
                              context.pop();
                              await _syncNetworkFolder(
                                selectUpdatePageNumKey
                                    .currentState!
                                    .updatePageNum,
                              );
                            },
                          ),
                        ],
                      );
                    },
                    child: Builder(
                      builder: (context) {
                        return IconButton(
                          icon: const Icon(Icons.sync),
                          onPressed: () {
                            Flyout.of(context).show();
                          },
                        );
                      },
                    ),
                  ),
                ),
              Tooltip(
                message: "Filter".tl,
                child: IconButton(
                  icon: const Icon(Icons.sort_rounded),
                  color: readFilterSelect != readFilterList[0]
                      ? context.colorScheme.primaryContainer
                      : null,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return _LocalFavoritesFilterDialog(
                          initReadFilterSelect: readFilterSelect,
                          updateConfig: (readFilter) {
                            setState(() {
                              readFilterSelect = readFilter;
                            });
                            updateComics();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              Tooltip(
                message: "Search".tl,
                child: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      keyword = "";
                      searchMode = true;
                      updateSearchResult();
                    });
                  },
                ),
              ),
              if (!isAllFolder)
                MenuButton(
                  entries: [
                    MenuEntry(
                      icon: Icons.edit_outlined,
                      text: "Rename".tl,
                      onClick: () {
                        showInputDialog(
                          context: context,
                          title: "Rename".tl,
                          hintText: "New Name".tl,
                          onConfirm: (value) {
                            var err = validateFolderName(value.toString());
                            if (err != null) {
                              return err;
                            }
                            favoritesRepo.rename(
                              widget.folder,
                              value.toString(),
                            );
                            favPage.folderList?.updateFolders();
                            favPage.setFolder(false, value.toString());
                            return null;
                          },
                        );
                      },
                    ),
                    MenuEntry(
                      icon: Icons.reorder,
                      text: "Reorder".tl,
                      onClick: () {
                        unawaited(() async {
                          await context.to(() {
                            return _ReorderComicsPage(widget.folder, (comics) {
                              this.comics = comics;
                            });
                          });
                          if (!mounted) {
                            return;
                          }
                          setState(() {});
                        }());
                      },
                    ),
                    MenuEntry(
                      icon: Icons.upload_file,
                      text: "Export".tl,
                      onClick: () {
                        var json = favoritesRepo.folderToJson(widget.folder);
                        saveFile(
                          data: utf8.encode(json),
                          filename: "${widget.folder}.json",
                        );
                      },
                    ),
                    MenuEntry(
                      icon: Icons.update,
                      text: "Update Comics Info".tl,
                      onClick: () async {
                        final newComics = await updateComicsInfo(
                          context,
                          widget.folder,
                        );
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          comics = newComics;
                        });
                      },
                    ),
                    MenuEntry(
                      icon: Icons.delete_outline,
                      text: "Delete Folder".tl,
                      color: context.colorScheme.error,
                      onClick: () {
                        showConfirmDialog(
                          context: context,
                          title: "Delete".tl,
                          content: "Delete folder '@f' ?".tlParams({
                            "f": widget.folder,
                          }),
                          btnColor: context.colorScheme.error,
                          onConfirm: () {
                            favPage.setFolder(false, null);
                            favoritesRepo.deleteFolder(widget.folder);
                            favPage.folderList?.updateFolders();
                          },
                        );
                      },
                    ),
                  ],
                ),
            ],
          )
        else if (multiSelectMode)
          SliverAppbar(
            style: context.width < changePoint
                ? AppbarStyle.shadow
                : AppbarStyle.blur,
            leading: Tooltip(
              message: "Cancel".tl,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    multiSelectMode = false;
                    selectedComics.clear();
                  });
                },
              ),
            ),
            title: Text(
              "Selected @c comics".tlParams({"c": selectedComics.length}),
            ),
            actions: [
              MenuButton(
                entries: [
                  if (!isAllFolder)
                    MenuEntry(
                      icon: Icons.drive_file_move,
                      text: "Move to folder".tl,
                      onClick: () => favoriteOption('move'),
                    ),
                  if (!isAllFolder)
                    MenuEntry(
                      icon: Icons.copy,
                      text: "Copy to folder".tl,
                      onClick: () => favoriteOption('add'),
                    ),
                  MenuEntry(
                    icon: Icons.select_all,
                    text: "Select All".tl,
                    onClick: selectAll,
                  ),
                  MenuEntry(
                    icon: Icons.deselect,
                    text: "Deselect".tl,
                    onClick: _cancel,
                  ),
                  MenuEntry(
                    icon: Icons.flip,
                    text: "Invert Selection".tl,
                    onClick: invertSelection,
                  ),
                  if (!isAllFolder)
                    MenuEntry(
                      icon: Icons.delete_outline,
                      text: "Delete Comic".tl,
                      color: context.colorScheme.error,
                      onClick: () {
                        showConfirmDialog(
                          context: context,
                          title: "Delete".tl,
                          content: "Delete @c comics?".tlParams({
                            "c": selectedComics.length,
                          }),
                          btnColor: context.colorScheme.error,
                          onConfirm: () {
                            _deleteComicWithId();
                          },
                        );
                      },
                    ),
                  MenuEntry(
                    icon: Icons.download,
                    text: "Download".tl,
                    onClick: () {
                      unawaited(downloadSelected());
                    },
                  ),
                  if (selectedComics.length == 1)
                    MenuEntry(
                      icon: Icons.copy,
                      text: "Copy Title".tl,
                      onClick: () {
                        Clipboard.setData(
                          ClipboardData(text: selectedComics.keys.first.title),
                        );
                        context.showMessage(message: "Copied".tl);
                      },
                    ),
                  if (selectedComics.length == 1)
                    MenuEntry(
                      icon: Icons.chrome_reader_mode_outlined,
                      text: "Read".tl,
                      onClick: () {
                        final c = selectedComics.keys.first as FavoriteItem;
                        unawaited(_openFavoriteComic(c));
                      },
                    ),
                  if (selectedComics.length == 1)
                    MenuEntry(
                      icon: Icons.arrow_forward_ios,
                      text: "Jump to Detail".tl,
                      onClick: () {
                        final c = selectedComics.keys.first as FavoriteItem;
                        context.to(
                          () => ComicPage(id: c.id, sourceKey: c.sourceKey),
                        );
                      },
                    ),
                ],
              ),
            ],
          )
        else if (searchMode)
          SliverAppbar(
            style: context.width < changePoint
                ? AppbarStyle.shadow
                : AppbarStyle.blur,
            leading: Tooltip(
              message: "Cancel".tl,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    searchMode = false;
                  });
                },
              ),
            ),
            title: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Search".tl,
                border: UnderlineInputBorder(),
              ),
              onChanged: (v) {
                keyword = v;
                searchHasUpper = keyword.contains(RegExp(r'[A-Z]'));
                updateSearchResult();
              },
            ).paddingBottom(8).paddingRight(8),
          ),
        if (isLoading)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: const Center(child: CircularProgressIndicator()),
            ),
          )
        else
          SliverGridComics(
            comics: searchMode ? searchResults : filterComics(comics),
            selections: selectedComics,
            menuBuilder: (c) {
              return [
                if (!isAllFolder)
                  MenuEntry(
                    icon: Icons.delete,
                    text: "Delete".tl,
                    onClick: () {
                      favoritesRepo.deleteComicWithId(
                        widget.folder,
                        c.id,
                        (c as FavoriteItem).type,
                      );
                    },
                  ),
                MenuEntry(
                  icon: Icons.check,
                  text: "Select".tl,
                  onClick: () {
                    setState(() {
                      if (!multiSelectMode) {
                        multiSelectMode = true;
                      }
                      if (selectedComics.containsKey(c as FavoriteItem)) {
                        selectedComics.remove(c);
                        _checkExitSelectMode();
                      } else {
                        selectedComics[c] = true;
                      }
                      lastSelectedIndex = comics.indexOf(c);
                    });
                  },
                ),
                MenuEntry(
                  icon: Icons.download,
                  text: "Download".tl,
                  onClick: () {
                    unawaited(downloadComic(c as FavoriteItem));
                    context.showMessage(message: "Download started".tl);
                  },
                ),
                if (appdata.settings["onClickFavorite"] == "viewDetail")
                  MenuEntry(
                    icon: Icons.menu_book_outlined,
                    text: "Read".tl,
                    onClick: () {
                      unawaited(_openFavoriteComic(c as FavoriteItem));
                    },
                  ),
              ];
            },
            onTap: (c, heroTag) {
              if (multiSelectMode) {
                setState(() {
                  if (selectedComics.containsKey(c as FavoriteItem)) {
                    selectedComics.remove(c);
                    _checkExitSelectMode();
                  } else {
                    selectedComics[c] = true;
                  }
                  lastSelectedIndex = comics.indexOf(c);
                });
              } else if (appdata.settings["onClickFavorite"] == "viewDetail") {
                context.to(
                  () => ComicPage(
                    id: c.id,
                    sourceKey: c.sourceKey,
                    cover: c.cover,
                    title: c.title,
                    heroTag: heroTag,
                  ),
                );
              } else {
                unawaited(_openFavoriteComic(c as FavoriteItem));
              }
            },
            onLongPressed: (c, heroTag) {
              setState(() {
                if (!multiSelectMode) {
                  multiSelectMode = true;
                  if (!selectedComics.containsKey(c as FavoriteItem)) {
                    selectedComics[c] = true;
                  }
                  lastSelectedIndex = comics.indexOf(c);
                } else {
                  if (lastSelectedIndex != null) {
                    int start = lastSelectedIndex!;
                    int end = comics.indexOf(c as FavoriteItem);
                    if (start > end) {
                      int temp = start;
                      start = end;
                      end = temp;
                    }

                    for (int i = start; i <= end; i++) {
                      if (i == lastSelectedIndex) continue;

                      var comic = comics[i];
                      if (selectedComics.containsKey(comic)) {
                        selectedComics.remove(comic);
                      } else {
                        selectedComics[comic] = true;
                      }
                    }
                  }
                  lastSelectedIndex = comics.indexOf(c as FavoriteItem);
                }
                _checkExitSelectMode();
              });
            },
          ),
      ],
    );
    body = AppScrollBar(
      topPadding: 48,
      controller: scrollController,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: body,
      ),
    );
    return PopScope(
      canPop: !multiSelectMode && !searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        } else if (searchMode) {
          setState(() {
            searchMode = false;
            keyword = "";
            updateComics();
          });
        }
      },
      child: body,
    );
  }

  void favoriteOption(String option) {
    var targetFolders = favoritesRepo.folderNames
        .where((folder) => folder != favPage.folder)
        .toList();

    showPopUpWidget(
      context,
      StatefulBuilder(
        builder: (context, setState) {
          return PopUpWidgetScaffold(
            title: favPage.folder ?? "Unselected".tl,
            body: Padding(
              padding: EdgeInsets.only(bottom: context.padding.bottom + 16),
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 700,
                  maxWidth: 500,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: targetFolders.length + 1,
                        itemBuilder: (context, index) {
                          if (index == targetFolders.length) {
                            return SizedBox(
                              height: 36,
                              child: Center(
                                child: TextButton(
                                  onPressed: () {
                                    unawaited(() async {
                                      await newFolder(context);
                                      if (!context.mounted) {
                                        return;
                                      }
                                      setState(() {
                                        targetFolders = favoritesRepo
                                            .folderNames
                                            .where(
                                              (folder) =>
                                                  folder != favPage.folder,
                                            )
                                            .toList();
                                      });
                                    }());
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.add, size: 20),
                                      const SizedBox(width: 4),
                                      Text("New Folder".tl),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          var folder = targetFolders[index];
                          var disabled = false;
                          if (selectedLocalFolders.isNotEmpty) {
                            if (added.contains(folder) &&
                                !added.contains(selectedLocalFolders.first)) {
                              disabled = true;
                            } else if (!added.contains(folder) &&
                                added.contains(selectedLocalFolders.first)) {
                              disabled = true;
                            }
                          }
                          return CheckboxListTile(
                            title: Row(
                              children: [
                                Text(folder),
                                const SizedBox(width: 8),
                              ],
                            ),
                            value: selectedLocalFolders.contains(folder),
                            onChanged: disabled
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v!) {
                                        selectedLocalFolders.add(folder);
                                      } else {
                                        selectedLocalFolders.remove(folder);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                    Center(
                      child: FilledButton(
                        onPressed: () {
                          if (selectedLocalFolders.isEmpty) {
                            return;
                          }
                          if (option == 'move') {
                            var comics = selectedComics.keys
                                .map((e) => e as FavoriteItem)
                                .toList();
                            for (var f in selectedLocalFolders) {
                              favoritesRepo.batchMoveFavorites(
                                favPage.folder as String,
                                f,
                                comics,
                              );
                            }
                          } else {
                            var comics = selectedComics.keys
                                .map((e) => e as FavoriteItem)
                                .toList();
                            for (var f in selectedLocalFolders) {
                              favoritesRepo.batchCopyFavorites(
                                favPage.folder as String,
                                f,
                                comics,
                              );
                            }
                          }
                          context.pop();
                          updateComics();
                          _cancel();
                        },
                        child: Text(option == 'move' ? "Move".tl : "Add".tl),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _checkExitSelectMode() {
    if (selectedComics.isEmpty) {
      setState(() {
        multiSelectMode = false;
      });
    }
  }

  void _cancel() {
    setState(() {
      selectedComics.clear();
      multiSelectMode = false;
    });
  }

  void _deleteComicWithId() {
    var toBeDeleted = selectedComics.keys
        .map((e) => e as FavoriteItem)
        .toList();
    favoritesRepo.batchDeleteComics(widget.folder, toBeDeleted);
    _cancel();
  }
}

class _ReorderComicsPage extends StatefulWidget {
  const _ReorderComicsPage(this.name, this.onReorder);

  final String name;

  final void Function(List<FavoriteItem>) onReorder;

  @override
  State<_ReorderComicsPage> createState() => _ReorderComicsPageState();
}

class _ReorderComicsPageState extends State<_ReorderComicsPage> {
  final _key = GlobalKey();
  var reorderWidgetKey = UniqueKey();
  final _scrollController = ScrollController();
  late var comics = favoritesRepo.getFolderComics(widget.name);
  bool changed = false;

  static int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  Color lightenColor(Color color, double lightenValue) {
    int red = (_floatToInt8(color.r) + ((255 - color.r) * lightenValue))
        .round();
    int green = (_floatToInt8(color.g) * 255 + ((255 - color.g) * lightenValue))
        .round();
    int blue = (_floatToInt8(color.b) * 255 + ((255 - color.b) * lightenValue))
        .round();

    return Color.fromARGB(_floatToInt8(color.a), red, green, blue);
  }

  @override
  void dispose() {
    if (changed) {
      final reorderedComics = List<FavoriteItem>.of(comics);
      final folderName = widget.name;
      // Delay to ensure navigation is completed
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          favoritesRepo.reorder(reorderedComics, folderName);
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var type = appdata.settings['comicDisplayMode'];
    var tiles = comics.map((e) {
      var comicSource = e.type.comicSource;
      return ComicTile(
        key: Key(e.hashCode.toString()),
        enableLongPressed: false,
        comic: Comic(
          e.name,
          e.coverPath,
          e.id,
          e.author,
          e.tags,
          type == 'detailed'
              ? "${e.time} | ${comicSource?.name ?? "Unknown"}"
              : "${e.type.comicSource?.name ?? "Unknown"} | ${e.time}",
          comicSource?.key ?? (e.type == ComicType.local ? "local" : "Unknown"),
          null,
          null,
        ),
      );
    }).toList();
    return Scaffold(
      appBar: Appbar(
        title: Text("Reorder".tl),
        actions: [
          Tooltip(
            message: "Information".tl,
            child: IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                showInfoDialog(
                  context: context,
                  title: "Reorder".tl,
                  content: "Long press and drag to reorder.".tl,
                );
              },
            ),
          ),
          Tooltip(
            message: "Reverse".tl,
            child: IconButton(
              icon: const Icon(Icons.swap_vert),
              onPressed: () {
                setState(() {
                  comics = comics.reversed.toList();
                  changed = true;
                });
              },
            ),
          ),
        ],
      ),
      body: ReorderableBuilder<FavoriteItem>(
        key: reorderWidgetKey,
        scrollController: _scrollController,
        longPressDelay: App.isDesktop
            ? const Duration(milliseconds: 100)
            : const Duration(milliseconds: 500),
        onReorder: (reorderFunc) {
          changed = true;
          setState(() {
            comics = reorderFunc(comics);
          });
          widget.onReorder(comics);
        },
        dragChildBoxDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: lightenColor(
            Theme.of(context).splashColor.withAlpha(255),
            0.2,
          ),
        ),
        builder: (children) {
          return GridView(
            key: _key,
            controller: _scrollController,
            gridDelegate: SliverGridDelegateWithComics(),
            children: children,
          );
        },
        children: tiles,
      ),
    );
  }
}

class _SelectUpdatePageNum extends StatefulWidget {
  const _SelectUpdatePageNum({
    required this.networkSource,
    this.networkFolder,
    super.key,
  });

  final String? networkFolder;
  final String networkSource;

  @override
  State<_SelectUpdatePageNum> createState() => _SelectUpdatePageNumState();
}

class _SelectUpdatePageNumState extends State<_SelectUpdatePageNum> {
  int updatePageNum = 9999999;

  String get _allPageText => 'All'.tl;

  List<String> get pageNumList => [
    '1',
    '2',
    '3',
    '5',
    '10',
    '20',
    '50',
    '100',
    '200',
    _allPageText,
  ];

  @override
  void initState() {
    updatePageNum = readLocalFavoritesUpdatePageNumPreference(9999999);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var source = ComicSource.find(widget.networkSource);
    var sourceName = source?.name ?? widget.networkSource;
    var text = "The folder is Linked to @source".tlParams({
      "source": sourceName,
    });
    if (widget.networkFolder != null && widget.networkFolder!.isNotEmpty) {
      text += "\n${"Source Folder".tl}: ${widget.networkFolder}";
    }

    return Column(
      children: [
        Row(children: [Text(text)]),
        Row(
          children: [
            Text("Update the page number by the latest collection".tl),
            Spacer(),
            Select(
              current: updatePageNum.toString() == '9999999'
                  ? _allPageText
                  : updatePageNum.toString(),
              values: pageNumList,
              minWidth: 48,
              onTap: (index) {
                setState(() {
                  updatePageNum = int.parse(
                    pageNumList[index] == _allPageText
                        ? '9999999'
                        : pageNumList[index],
                  );
                  appdata.implicitData["local_favorites_update_page_num"] =
                      updatePageNum;
                  appdata.writeImplicitData();
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _LocalFavoritesFilterDialog extends StatefulWidget {
  const _LocalFavoritesFilterDialog({
    required this.initReadFilterSelect,
    required this.updateConfig,
  });

  final String initReadFilterSelect;
  final Function updateConfig;

  @override
  State<_LocalFavoritesFilterDialog> createState() =>
      _LocalFavoritesFilterDialogState();
}

const readFilterList = ['All', 'UnCompleted', 'Completed'];

class _LocalFavoritesFilterDialogState
    extends State<_LocalFavoritesFilterDialog> {
  List<String> optionTypes = ['Filter'];
  late var readFilter = widget.initReadFilterSelect;
  @override
  Widget build(BuildContext context) {
    Widget tabBar = Material(
      borderRadius: BorderRadius.circular(8),
      child: AppTabBar(
        key: PageStorageKey(optionTypes),
        tabs: optionTypes.map((e) => Tab(text: e.tl, key: Key(e))).toList(),
      ),
    ).paddingTop(context.padding.top);
    return ContentDialog(
      content: DefaultTabController(
        length: optionTypes.length,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tabBar,
            TabViewBody(
              children: [
                Column(
                  children: [
                    ListTile(
                      title: Text("Filter reading status".tl),
                      trailing: Select(
                        current: readFilter.tl,
                        values: readFilterList.map((e) => e.tl).toList(),
                        minWidth: 64,
                        onTap: (index) {
                          setState(() {
                            readFilter = readFilterList[index];
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            appdata.implicitData["local_favorites_read_filter"] = readFilter;
            appdata.writeImplicitData();
            if (mounted) {
              Navigator.pop(context);
              widget.updateConfig(readFilter);
            }
          },
          child: Text("Confirm".tl),
        ),
      ],
    );
  }
}
