part of 'comic_page.dart';

@visibleForTesting
SourceRef resolveComicDetailsReadSourceRef({
  required String comicId,
  required String sourceKey,
  required ComicChapters? chapters,
  required int? ep,
  required int? group,
  required SourceRef? resumeSourceRef,
}) {
  return resolveReaderTargetSourceRef(
    comicId: comicId,
    sourceKey: sourceKey,
    chapters: chapters,
    ep: ep,
    group: group,
    resumeSourceRef: resumeSourceRef,
  );
}

@visibleForTesting
class ComicDetailReaderOpenRequest {
  const ComicDetailReaderOpenRequest({
    required this.comicId,
    required this.sourceRef,
    this.initialEp,
    this.initialPage,
    this.initialGroup,
  });

  final String comicId;
  final SourceRef sourceRef;
  final int? initialEp;
  final int? initialPage;
  final int? initialGroup;

  String get sourceKey => sourceRef.sourceKey;

  String? get chapterRefId => sourceRef.params['chapterId']?.toString();
}

@visibleForTesting
ComicDetailReaderOpenRequest buildComicDetailReaderOpenRequest({
  required ComicDetails comic,
  required SourceRef sourceRef,
  required int? ep,
  required int? page,
  required int? group,
}) {
  final resolvedComicId =
      sourceRef.params['localComicId']?.toString() ??
      sourceRef.params['comicId']?.toString() ??
      comic.id;
  return ComicDetailReaderOpenRequest(
    comicId: resolvedComicId,
    sourceRef: sourceRef,
    initialEp: ep,
    initialPage: page,
    initialGroup: group,
  );
}

@visibleForTesting
bool shouldBypassReaderNextForComicDetailRead({required String sourceKey}) {
  return isLocalSourceKey(sourceKey);
}

abstract mixin class _ComicPageActions {
  void update();

  void retry();

  ComicDetails get comic;

  String? get canonicalComicId;

  ComicSource get comicSource => ComicSource.find(comic.sourceKey)!;

  History? get history;

  bool isLiking = false;

  bool isLiked = false;

  void likeOrUnlike() async {
    if (isLiking) return;
    isLiking = true;
    update();
    var res = await comicSource.likeOrUnlikeComic!(comic.id, isLiked);
    if (res.error) {
      App.rootContext.showMessage(message: res.errorMessage!);
    } else {
      isLiked = !isLiked;
    }
    isLiking = false;
    update();
  }

  /// whether the comic is added to local favorite
  bool isAddToLocalFav = false;

  /// whether the comic is favorite on the server
  bool isFavorite = false;

  FavoriteItem _toFavoriteItem() {
    var tags = <String>[];
    for (var e in comic.tags.entries) {
      tags.addAll(e.value.map((tag) => '${e.key}:$tag'));
    }
    return FavoriteItem(
      id: comic.id,
      name: comic.title,
      coverPath: comic.cover,
      author: comic.subTitle ?? comic.uploader ?? '',
      type: comic.comicType,
      tags: tags,
    );
  }

  void openFavPanel() {
    showSideBar(
      App.rootContext,
      _FavoritePanel(
        cid: comic.id,
        type: comic.comicType,
        isFavorite: isFavorite,
        onFavorite: (local, network) {
          if (network != null) {
            isFavorite = network;
          }
          if (local != null) {
            isAddToLocalFav = local;
          }
          update();
        },
        favoriteItem: _toFavoriteItem(),
        updateTime: comic.findUpdateTime(),
      ),
    );
  }

  void quickFavorite() {
    var folder = appdata.settings['quickFavorite'];
    if (folder is! String) {
      return;
    }
    legacyAddLocalFavorite(folder, _toFavoriteItem(), comic.findUpdateTime());
    isAddToLocalFav = true;
    update();
    App.rootContext.showMessage(message: "Added".tl);
  }

  void share() {
    var text = comic.title;
    if (comic.url != null) {
      text += '\n${comic.url}';
    }
    Share.shareText(text);
  }

  /// read the comic
  ///
  /// [ep] the episode number, start from 1
  ///
  /// [page] the page number, start from 1
  ///
  /// [group] the chapter group number, start from 1
  Future<void> read([int? ep, int? page, int? group]) async {
    final resumeSourceRef = await ReaderResumeService(
      readerSessions: App.repositories.readerSession,
    ).loadPreferredResumeSourceRef(comic.id, comic.comicType);
    final sourceRef = resolveComicDetailsReadSourceRef(
      comicId: comic.id,
      sourceKey: comic.comicType.sourceKey,
      chapters: comic.chapters,
      ep: ep,
      group: group,
      resumeSourceRef: resumeSourceRef,
    );
    final request = buildComicDetailReaderOpenRequest(
      comic: comic,
      sourceRef: sourceRef,
      ep: ep,
      page: page,
      group: group,
    );
    Future<void> openLegacyReader() async {
      await App.rootContext
          .to(
            () => ReaderWithLoading(
              id: request.comicId,
              sourceRef: request.sourceRef,
              sourceKey: request.sourceKey,
              initialEp: request.initialEp,
              initialPage: request.initialPage,
              initialGroup: request.initialGroup,
            ),
          )
          .then((_) {
            onReadEnd();
          });
    }
    if (shouldBypassReaderNextForComicDetailRead(sourceKey: request.sourceKey)) {
      await openLegacyReader();
      return;
    }
    final readerNextEnabled = isReaderNextEnabledSetting(
      appdata.settings['reader_next_enabled'],
    );
    await routeComicDetailReadOpen(
      readerNextEnabled: readerNextEnabled,
      sourceKey: request.sourceKey,
      comicId: request.comicId,
      chapterRefId: request.chapterRefId,
      onDiagnostic: (packet) {
        Log.info(
          'ReaderNextCutoverDryRun',
          'routeDecision=${packet.routeDecision.name} '
              'featureFlagEnabled=${packet.featureFlagEnabled} '
              'sourceKey=${packet.sourceKey} '
              'canonicalComicId=${packet.canonicalComicIdRedacted} '
              'upstreamComicRefId=${packet.upstreamComicRefIdRedacted} '
              'chapterRefId=${packet.chapterRefIdRedacted} '
              'bridgeResultCode=${packet.bridgeResultCode}',
        );
      },
      openLegacy: openLegacyReader,
      openReaderNext: (_) async => openLegacyReader(),
      onBridgeBlocked: (diagnostic) async {
        App.rootContext.showMessage(
          message:
              'ReaderNext blocked: ${diagnostic.code.name} (${diagnostic.message})',
        );
      },
    );
  }

  void continueRead() {
    var ep = history?.ep ?? 1;
    var page = history?.page ?? 1;
    var group = history?.group;
    read(ep, page, group);
  }

  void onReadEnd();

  void download() async {
    final runtimeComicId = canonicalComicId ?? comic.id;
    if (legacyIsDownloading(comic.id, comic.comicType)) {
      App.rootContext.showMessage(message: "The comic is downloading".tl);
      return;
    }
    if (comic.chapters == null &&
        await App.repositories.localLibrary.hasPrimaryLocalLibraryItem(
          runtimeComicId,
        )) {
      App.rootContext.showMessage(message: "The comic is downloaded".tl);
      return;
    }

    if (comicSource.archiveDownloader != null) {
      bool useNormalDownload = false;
      List<ArchiveInfo>? archives;
      int selected = -1;
      bool isLoading = false;
      bool isGettingLink = false;
      await showDialog(
        context: App.rootContext,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return ContentDialog(
                title: "Download".tl,
                content: RadioGroup<int>(
                  groupValue: selected,
                  onChanged: (v) {
                    setState(() {
                      selected = v ?? selected;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(value: -1, title: Text("Normal".tl)),
                      ExpansionTile(
                        title: Text("Archive".tl),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        collapsedShape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        onExpansionChanged: (b) {
                          if (!isLoading && b && archives == null) {
                            isLoading = true;
                            comicSource.archiveDownloader!
                                .getArchives(comic.id)
                                .then((value) {
                                  if (value.success) {
                                    archives = value.data;
                                  } else {
                                    App.rootContext.showMessage(
                                      message: value.errorMessage!,
                                    );
                                  }
                                  setState(() {
                                    isLoading = false;
                                  });
                                });
                          }
                        },
                        children: [
                          if (archives == null)
                            const ListLoadingIndicator().toCenter()
                          else
                            for (int i = 0; i < archives!.length; i++)
                              RadioListTile<int>(
                                value: i,
                                title: Text(archives![i].title),
                                subtitle: Text(archives![i].description),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  Button.filled(
                    isLoading: isGettingLink,
                    onPressed: () async {
                      if (selected == -1) {
                        useNormalDownload = true;
                        context.pop();
                        return;
                      }
                      setState(() {
                        isGettingLink = true;
                      });
                      var res = await comicSource.archiveDownloader!
                          .getDownloadUrl(comic.id, archives![selected].id);
                      if (res.error) {
                        App.rootContext.showMessage(message: res.errorMessage!);
                        setState(() {
                          isGettingLink = false;
                        });
                      } else if (context.mounted) {
                        if (res.data.isNotEmpty) {
                          legacyAddDownloadTask(
                            ArchiveDownloadTask(res.data, comic),
                          );
                          App.rootContext.showMessage(
                            message: "Download started".tl,
                          );
                        }
                        context.pop();
                      }
                    },
                    child: Text("Confirm".tl),
                  ),
                ],
              );
            },
          );
        },
      );
      if (!useNormalDownload) {
        return;
      }
    }

    if (comic.chapters == null) {
      legacyAddDownloadTask(
        ImagesDownloadTask(
          source: comicSource,
          comicId: comic.id,
          comic: comic,
        ),
      );
    } else {
      List<int>? selected;
      var downloaded = <int>[];
      final downloadedChapterIds = await App.repositories.localLibrary
          .loadDownloadedChapterIds(runtimeComicId);
      if (downloadedChapterIds.isNotEmpty) {
        for (int i = 0; i < comic.chapters!.length; i++) {
          if (downloadedChapterIds.contains(comic.chapters!.ids.elementAt(i))) {
            downloaded.add(i);
          }
        }
      }
      await showSideBar(
        App.rootContext,
        _SelectDownloadChapter(
          comic.chapters!.titles.toList(),
          (v) => selected = v,
          downloaded,
        ),
      );
      if (selected == null) return;
      legacyAddDownloadTask(
        ImagesDownloadTask(
          source: comicSource,
          comicId: comic.id,
          comic: comic,
          chapters: selected!.map((i) {
            return comic.chapters!.ids.elementAt(i);
          }).toList(),
        ),
      );
    }
    App.rootContext.showMessage(message: "Download started".tl);
    update();
  }

  void onTapTag(String tag, String namespace) {
    var target = comicSource.handleClickTagEvent?.call(namespace, tag);
    var context = App.mainNavigatorKey!.currentContext!;
    target?.jump(context);
  }

  Future<void> manageLocalUserTags() async {
    final targetComicId = canonicalComicId;
    if (targetComicId == null) {
      return;
    }
    final existing = await App.repositories.comicUserTags.loadUserTagsForComic(
      targetComicId,
    );
    final tags = existing.map((tag) => tag.name).toList(growable: true);
    final controller = TextEditingController();
    var saved = false;
    await showDialog(
      context: App.rootContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            void addTag(String value) {
              final trimmed = value.trim();
              if (trimmed.isEmpty) {
                return;
              }
              if (tags.any(
                (tag) => tag.toLowerCase() == trimmed.toLowerCase(),
              )) {
                controller.clear();
                return;
              }
              setState(() {
                tags.add(trimmed);
                tags.sort((left, right) => left.compareTo(right));
                controller.clear();
              });
            }

            return ContentDialog(
              title: 'User Tags'.tl,
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      runSpacing: 8,
                      spacing: 8,
                      children: [
                        for (final tag in tags)
                          InputChip(
                            label: Text(tag),
                            onDeleted: () {
                              setState(() {
                                tags.remove(tag);
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'Add tag'.tl,
                        suffixIcon: IconButton(
                          onPressed: () => addTag(controller.text),
                          icon: const Icon(Icons.add),
                        ),
                      ),
                      onSubmitted: addTag,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancel'.tl),
                ),
                FilledButton(
                  onPressed: () async {
                    await _saveCanonicalUserTags(targetComicId, tags);
                    saved = true;
                    if (App.rootContext.mounted) {
                      App.rootContext.showMessage(message: 'Saved'.tl);
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Text('Confirm'.tl),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (saved) {
      retry();
    }
  }

  Future<void> _saveCanonicalUserTags(
    String targetComicId,
    List<String> tags,
  ) async {
    await App.repositories.comicUserTags.saveComicTags(
      comicId: targetComicId,
      tags: tags,
    );
  }

  void showMoreActions() {
    var context = App.rootContext;
    showMenuX(context, Offset(context.width - 16, context.padding.top), [
      MenuEntry(
        icon: Icons.copy,
        text: "Copy Title".tl,
        onClick: () {
          Clipboard.setData(ClipboardData(text: comic.title));
          context.showMessage(message: "Copied".tl);
        },
      ),
      if (!isLocalSourceKey(comic.sourceKey))
        MenuEntry(
          icon: Icons.copy_rounded,
          text: "Copy ID".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: comic.id));
            context.showMessage(message: "Copied".tl);
          },
        ),
      if (canonicalComicId != null)
        MenuEntry(
          icon: Icons.sell_outlined,
          text: 'User Tags'.tl,
          onClick: () {
            manageLocalUserTags();
          },
        ),
      if (comic.url != null)
        MenuEntry(
          icon: Icons.link,
          text: "Copy URL".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: comic.url!));
            context.showMessage(message: "Copied".tl);
          },
        ),
      if (comic.url != null)
        MenuEntry(
          icon: Icons.open_in_browser,
          text: "Open in Browser".tl,
          onClick: () {
            launchUrlString(comic.url!);
          },
        ),
    ]);
  }

  void showComments() {
    showSideBar(
      App.rootContext,
      CommentsPage(data: comic, source: comicSource),
    );
  }

  void starRating() {
    if (!comicSource.isLogged) {
      return;
    }
    var rating = 0.0;
    var isLoading = false;
    showDialog(
      context: App.rootContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => SimpleDialog(
          title: const Text("Rating"),
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 100,
              child: Center(
                child: SizedBox(
                  width: 210,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      RatingWidget(
                        padding: 2,
                        onRatingUpdate: (value) => rating = value,
                        value: 1,
                        selectable: true,
                        size: 40,
                      ),
                      const Spacer(),
                      Button.filled(
                        isLoading: isLoading,
                        onPressed: () {
                          setState(() {
                            isLoading = true;
                          });
                          comicSource.starRatingFunc!(comic.id, rating.round())
                              .then((value) {
                                if (value.success) {
                                  App.rootContext.showMessage(
                                    message: "Success".tl,
                                  );
                                  Navigator.of(dialogContext).pop();
                                } else {
                                  App.rootContext.showMessage(
                                    message: value.errorMessage!,
                                  );
                                  setState(() {
                                    isLoading = false;
                                  });
                                }
                              });
                        },
                        child: Text("Submit".tl),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
