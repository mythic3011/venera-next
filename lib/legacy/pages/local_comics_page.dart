import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/appdata_authority_audit.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/local/canonical_local_library_runtime.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';
import 'package:venera/foundation/reader/canonical_reader_pages.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/downloading_page.dart';
import 'package:venera/pages/favorites/favorites_page.dart';
import 'package:venera/utils/cbz.dart';
import 'package:venera/utils/epub.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/import_sort.dart';
import 'package:venera/utils/pdf.dart';
import 'package:venera/utils/translations.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:zip_flutter/zip_flutter.dart';

String readLocalSortPreference() {
  recordAppdataAuthorityDiagnostic(
    channel: 'appdata.audit',
    event: 'appdata.authority.access',
    key: 'local_sort',
    storage: AppdataAuditStorage.implicitData,
    access: 'read',
    data: const <String, Object?>{'owner': 'LocalComicsPage'},
  );
  return (appdata.implicitData['local_sort'] ?? 'name').toString();
}

bool canReorderLocalComicPages({
  required String comicBaseDir,
  required String localRootPath,
}) {
  return comicBaseDir.startsWith(localRootPath);
}

List<LocalComic> buildChapterMergeCandidates({
  required LocalComic targetComic,
  required List<LocalComic> allComics,
}) {
  return allComics
      .where(
        (comic) =>
            !(comic.id == targetComic.id &&
                comic.comicType == targetComic.comicType),
      )
      .toList();
}

List<String> reorderChapterIds({
  required List<String> chapterIds,
  required int oldIndex,
  required int newIndex,
}) {
  final reordered = List<String>.from(chapterIds);
  var targetIndex = newIndex;
  if (targetIndex > oldIndex) {
    targetIndex -= 1;
  }
  final moved = reordered.removeAt(oldIndex);
  reordered.insert(targetIndex, moved);
  return reordered;
}

Object resolveLocalChapterPageTarget({
  required bool hasChapters,
  required String? selectedChapterId,
}) {
  return hasChapters ? selectedChapterId! : 0;
}

ComicDetailPage buildLocalComicDetailEntry(
  LocalComic comic, {
  String? heroTag,
}) {
  return ComicDetailPage(
    comicId: comic.id,
    title: comic.title,
    heroTag: heroTag,
  );
}

String formatLocalChapterDisplayLabel({
  required int index,
  required String title,
}) {
  return "${index + 1}. $title";
}

String localImageUriToPath(String imageUri) {
  return imageUri.replaceFirst('file://', '');
}

const Set<String> _localComicImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'jpe',
};

bool _isLocalComicImageFile(File file) {
  final extension = file.extension.toLowerCase();
  return _localComicImageExtensions.contains(extension);
}

Map<String, List<String>> _discoverChapterImages(
  Directory comicDirectory,
  List<String> chapters,
) {
  final chapterImages = <String, List<String>>{};
  for (final chapter in chapters) {
    final chapterDirectory = Directory(
      FilePath.join(comicDirectory.path, chapter),
    );
    if (!chapterDirectory.existsSync()) {
      continue;
    }
    final images = chapterDirectory
        .listSync(recursive: false, followLinks: false)
        .whereType<File>()
        .where(_isLocalComicImageFile)
        .map((file) => file.name)
        .toList(growable: false);
    chapterImages[chapter] = images;
  }
  return chapterImages;
}

String? _selectDiscoveredCoverPath({
  required List<String> rootFiles,
  required Map<String, List<String>> chapterFiles,
}) {
  final sortedRoot = [...rootFiles]..sort(naturalCompare);
  for (final name in sortedRoot) {
    if (name.toLowerCase().startsWith('cover')) {
      return name;
    }
  }
  if (sortedRoot.isNotEmpty) {
    return sortedRoot.first;
  }
  if (chapterFiles.isEmpty) {
    return null;
  }
  final sortedChapters = chapterFiles.keys.toList()..sort(naturalCompare);
  for (final chapter in sortedChapters) {
    final files = [...(chapterFiles[chapter] ?? const <String>[])]
      ..sort(naturalCompare);
    if (files.isNotEmpty) {
      return '$chapter/${files.first}';
    }
  }
  return null;
}

LocalComic? buildDiscoveredLocalComicFromDirectory(
  Directory comicDirectory, {
  required String comicId,
  DateTime? createdAt,
}) {
  final rootFiles = comicDirectory
      .listSync(recursive: false, followLinks: false)
      .whereType<File>()
      .where(_isLocalComicImageFile)
      .map((file) => file.name)
      .toList(growable: false);
  final chapters = comicDirectory
      .listSync(recursive: false, followLinks: false)
      .whereType<Directory>()
      .map((dir) => dir.name)
      .toList(growable: false);
  final chapterImages = _discoverChapterImages(comicDirectory, chapters);
  final hasAnyChapterImages = chapterImages.values.any(
    (files) => files.isNotEmpty,
  );
  if (rootFiles.isEmpty && !hasAnyChapterImages) {
    return null;
  }
  chapters.sort(naturalCompare);
  final cover = _selectDiscoveredCoverPath(
    rootFiles: rootFiles,
    chapterFiles: chapterImages,
  );
  if (cover == null || cover.isEmpty) {
    return null;
  }
  final hasChapters = chapters.isNotEmpty;
  return LocalComic(
    id: comicId,
    title: comicDirectory.name,
    subtitle: '',
    tags: const [],
    directory: comicDirectory.name,
    chapters: hasChapters
        ? ComicChapters(Map.fromIterables(chapters, chapters))
        : null,
    cover: cover,
    comicType: ComicType.local,
    downloadedChapters: chapters,
    createdAt: createdAt ?? DateTime.now(),
  );
}

List<LocalComic> applyCanonicalLocalLibraryView({
  required List<LocalComic> comics,
  required List<LocalLibraryBrowseItem> browseRecords,
  Set<String>? visibleComicIds,
  required LocalSortType sortType,
  String keyword = '',
}) {
  final browseByComicId = {
    for (final record in browseRecords) record.comicId: record,
  };
  final normalizedKeyword = keyword.trim().toLowerCase();
  var visible = comics
      .where((comic) {
        if (visibleComicIds != null && !visibleComicIds.contains(comic.id)) {
          return false;
        }
        if (normalizedKeyword.isEmpty) {
          return true;
        }
        final browse = browseByComicId[comic.id];
        final fields = <String>[
          comic.title,
          comic.subtitle,
          ...comic.tags,
          if (browse != null) browse.title,
          if (browse != null) ...browse.userTags,
          if (browse != null) ...browse.sourceTags,
        ];
        return fields.any(
          (field) => field.toLowerCase().contains(normalizedKeyword),
        );
      })
      .toList(growable: false);
  visible.sort((left, right) {
    final leftBrowse = browseByComicId[left.id];
    final rightBrowse = browseByComicId[right.id];
    if (sortType == LocalSortType.name) {
      final leftTitle = (leftBrowse?.title ?? left.title).toLowerCase();
      final rightTitle = (rightBrowse?.title ?? right.title).toLowerCase();
      final byTitle = leftTitle.compareTo(rightTitle);
      if (byTitle != 0) {
        return byTitle;
      }
      return left.id.compareTo(right.id);
    }
    final leftDate =
        DateTime.tryParse(
          leftBrowse?.updatedAt ?? left.createdAt.toIso8601String(),
        ) ??
        left.createdAt;
    final rightDate =
        DateTime.tryParse(
          rightBrowse?.updatedAt ?? right.createdAt.toIso8601String(),
        ) ??
        right.createdAt;
    final byDate = leftDate.compareTo(rightDate);
    if (byDate != 0) {
      return sortType == LocalSortType.timeAsc ? byDate : -byDate;
    }
    return left.id.compareTo(right.id);
  });
  return visible;
}

class _LocalComicsGateway {
  _LocalComicsGateway()
    : _runtime = CanonicalLocalLibraryRuntimeService(
        store: App.unifiedComicsStore,
      );

  final CanonicalLocalLibraryRuntimeService _runtime;
  String? _localRootPath;

  Future<void> ensureInitialized() async {
    _localRootPath = await _runtime.requireRootPath();
  }

  bool get isInitialized => _localRootPath != null;

  void addListener(VoidCallback listener) {}

  void removeListener(VoidCallback listener) {}

  Future<List<LocalComic>> getComics(LocalSortType sortType) {
    return _runtime.loadAvailableComics();
  }

  Future<List<LocalComic>> search(String keyword) async {
    final comics = await _runtime.loadAvailableComics();
    final normalizedKeyword = keyword.trim().toLowerCase();
    return comics
        .where(
          (comic) =>
              normalizedKeyword.isEmpty ||
              comic.title.toLowerCase().contains(normalizedKeyword) ||
              comic.tags.any(
                (tag) => tag.toLowerCase().contains(normalizedKeyword),
              ),
        )
        .toList(growable: false);
  }

  Future<List<LocalComic>> getVisibleComics(
    LocalSortType sortType, {
    String keyword = '',
  }) async {
    final comics = await _runtime.loadAvailableComics(reconcile: true);
    final repository = App.repositories.localLibrary;
    final browseRecords = await repository.loadBrowseRecords();
    return applyCanonicalLocalLibraryView(
      comics: comics,
      browseRecords: browseRecords,
      sortType: sortType,
      keyword: keyword,
    );
  }

  Future<LocalComic?> findComic(String id, ComicType comicType) {
    return _runtime.loadComicById(id, reconcile: true);
  }

  Future<List<String>> loadImages(
    String comicId,
    ComicType comicType,
    Object chapterOrIndex,
  ) {
    return CanonicalReaderPages(
      store: App.repositories.comicDetailStore,
    ).loadLocalPages(
      localComicId: comicId,
      chapterId: chapterOrIndex is String ? chapterOrIndex : null,
    );
  }

  void renameChapter(LocalComic comic, String chapterId, String newName) =>
      legacyRenameLocalComicChapter(comic, chapterId, newName);

  void deleteChapters(LocalComic comic, List<String> chapters) =>
      legacyDeleteLocalComicChapters(comic, chapters);

  void batchDeleteComics(
    List<LocalComic> comics,
    bool removeComicFile,
    bool removeFavoriteAndHistory,
  ) => legacyBatchDeleteLocalComics(
    comics,
    removeComicFile,
    removeFavoriteAndHistory,
  );

  Future<void> reorderPages(
    LocalComic comic,
    Object chapterOrIndex,
    List<String> pageOrder,
  ) => legacyReorderLocalComicPages(comic, chapterOrIndex, pageOrder);

  Future<void> setCover(LocalComic comic, String coverPath) =>
      legacySetLocalComicCover(comic, coverPath);

  Future<void> addComicsAsChapters(
    LocalComic comic,
    List<LocalComic> sources, {
    required bool deleteSourceComics,
  }) => legacyAddComicsAsLocalChapters(
    comic,
    sources,
    deleteSourceComics: deleteSourceComics,
  );

  void reorderChapters(LocalComic comic, List<String> chapterIds) =>
      legacyReorderLocalComicChapters(comic, chapterIds);

  String get localRootPath => _localRootPath ?? '';

  Future<int> recheckAppDataLocalDirectory() async {
    _localRootPath ??= await _runtime.requireRootPath();
    return _runtime.recheck();
  }
}

class LocalComicsPage extends StatefulWidget {
  const LocalComicsPage({super.key});

  @override
  State<LocalComicsPage> createState() => _LocalComicsPageState();
}

class _RecheckLocalComicsIntent extends Intent {
  const _RecheckLocalComicsIntent();
}

class _LocalComicsPageState extends State<LocalComicsPage> {
  final _gateway = _LocalComicsGateway();

  List<LocalComic> comics = const [];

  late LocalSortType sortType;

  String keyword = "";

  bool searchMode = false;

  bool multiSelectMode = false;

  Map<LocalComic, bool> selectedComics = {};

  Future<List<LocalComic>> _loadComicsSnapshot() {
    return _gateway.getVisibleComics(sortType, keyword: keyword);
  }

  Future<void> update() async {
    final snapshot = await _loadComicsSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      comics = snapshot;
    });
  }

  Future<void> _recheckLocalComics() async {
    AppDiagnostics.info(
      'local.library',
      'local.library.recheckStarted',
      data: <String, Object?>{'keyword': keyword, 'sortType': sortType.value},
    );
    final added = await _gateway.recheckAppDataLocalDirectory();
    await update();
    AppDiagnostics.info(
      'local.library',
      'local.library.recheckCompleted',
      data: <String, Object?>{
        'addedCount': added,
        'visibleCount': comics.length,
      },
    );
  }

  @override
  void initState() {
    var sort = readLocalSortPreference();
    sortType = LocalSortType.fromString(sort);
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _gateway.ensureInitialized();
    if (!mounted) {
      return;
    }
    await update();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void sort() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Sort".tl,
              content: RadioGroup<LocalSortType>(
                groupValue: sortType,
                onChanged: (v) {
                  setState(() {
                    sortType = v ?? sortType;
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<LocalSortType>(
                      title: Text("Name".tl),
                      value: LocalSortType.name,
                    ),
                    RadioListTile<LocalSortType>(
                      title: Text("Date".tl),
                      value: LocalSortType.timeAsc,
                    ),
                    RadioListTile<LocalSortType>(
                      title: Text("Date Desc".tl),
                      value: LocalSortType.timeDesc,
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    appdata.implicitData["local_sort"] = sortType.value;
                    appdata.writeImplicitData();
                    Navigator.pop(context);
                    update();
                  },
                  child: Text("Confirm".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget buildMultiSelectMenu() {
    return MenuButton(
      entries: [
        MenuEntry(
          icon: Icons.delete_outline,
          text: "Delete".tl,
          onClick: () {
            deleteComics(selectedComics.keys.toList()).then((value) {
              if (value) {
                setState(() {
                  multiSelectMode = false;
                  selectedComics.clear();
                });
              }
            });
          },
        ),
        MenuEntry(
          icon: Icons.favorite_border,
          text: "Add to favorites".tl,
          onClick: () {
            addFavorite(context, selectedComics.keys.toList());
          },
        ),
        if (selectedComics.length == 1)
          MenuEntry(
            icon: Icons.folder_open,
            text: "Open Folder".tl,
            onClick: () {
              openComicFolder(context, selectedComics.keys.first);
            },
          ),
        if (selectedComics.length == 1)
          MenuEntry(
            icon: Icons.chrome_reader_mode_outlined,
            text: "View Detail".tl,
            onClick: () {
              context.to(
                () => buildLocalComicDetailEntry(selectedComics.keys.first),
              );
            },
          ),
        if (selectedComics.isNotEmpty)
          ...exportActions(selectedComics.keys.toList()),
      ],
    );
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
      buildMultiSelectMenu(),
    ];

    List<Widget> normalActions = [
      Tooltip(
        message: "Refresh".tl,
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            unawaited(_recheckLocalComics());
          },
        ),
      ),
      Tooltip(
        message: "Search".tl,
        child: IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              searchMode = true;
            });
          },
        ),
      ),
      Tooltip(
        message: "Sort".tl,
        child: IconButton(icon: const Icon(Icons.sort), onPressed: sort),
      ),
      Tooltip(
        message: "Downloading".tl,
        child: IconButton(
          icon: const Icon(Icons.download),
          onPressed: () {
            showPopUpWidget(context, const DownloadingPage());
          },
        ),
      ),
    ];

    var body = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.f4):
            const _RecheckLocalComicsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _RecheckLocalComicsIntent: CallbackAction<_RecheckLocalComicsIntent>(
            onInvoke: (_) {
              unawaited(_recheckLocalComics());
              return null;
            },
          ),
        },
        child: Scaffold(
          body: SmoothCustomScrollView(
            slivers: [
              if (!searchMode)
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
                      : Text("Local".tl),
                  actions: multiSelectMode ? selectActions : normalActions,
                )
              else if (searchMode)
                SliverAppbar(
                  leading: Tooltip(
                    message: multiSelectMode ? "Cancel".tl : "Cancel".tl,
                    child: IconButton(
                      icon: multiSelectMode
                          ? const Icon(Icons.close)
                          : const Icon(Icons.close),
                      onPressed: () {
                        if (multiSelectMode) {
                          setState(() {
                            multiSelectMode = false;
                            selectedComics.clear();
                          });
                        } else {
                          setState(() {
                            searchMode = false;
                            keyword = "";
                            update();
                          });
                        }
                      },
                    ),
                  ),
                  title: multiSelectMode
                      ? Text(selectedComics.length.toString())
                      : TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: "Search".tl,
                            border: InputBorder.none,
                          ),
                          onChanged: (v) {
                            keyword = v;
                            update();
                          },
                        ),
                  actions: multiSelectMode ? selectActions : null,
                ),
              SliverGridComics(
                comics: comics,
                selections: selectedComics,
                onLongPressed: (c, heroTag) {
                  setState(() {
                    multiSelectMode = true;
                    selectedComics[c as LocalComic] = true;
                  });
                },
                onTap: (c, heroTag) {
                  if (multiSelectMode) {
                    setState(() {
                      if (selectedComics.containsKey(c as LocalComic)) {
                        selectedComics.remove(c);
                      } else {
                        selectedComics[c] = true;
                      }
                      if (selectedComics.isEmpty) {
                        multiSelectMode = false;
                      }
                    });
                  } else {
                    context.to(
                      () => buildLocalComicDetailEntry(
                        c as LocalComic,
                        heroTag: heroTag,
                      ),
                    );
                  }
                },
                menuBuilder: (c) {
                  return [
                    MenuEntry(
                      icon: Icons.folder_open,
                      text: "Open Folder".tl,
                      onClick: () {
                        openComicFolder(context, c as LocalComic);
                      },
                    ),
                    MenuEntry(
                      icon: Icons.reorder,
                      text: "Reorder Pages".tl,
                      onClick: () {
                        showReorderPagesDialog(context, c as LocalComic);
                      },
                    ),
                    MenuEntry(
                      icon: Icons.image_outlined,
                      text: "Set Cover".tl,
                      onClick: () {
                        showSetCoverDialog(context, c as LocalComic);
                      },
                    ),
                    MenuEntry(
                      icon: Icons.view_list_outlined,
                      text: "Manage Chapters".tl,
                      onClick: () {
                        showManageChaptersDialog(context, c as LocalComic);
                      },
                    ),
                    MenuEntry(
                      icon: Icons.delete,
                      text: "Delete".tl,
                      onClick: () {
                        deleteComics([c as LocalComic]).then((value) {
                          if (value && multiSelectMode) {
                            setState(() {
                              multiSelectMode = false;
                              selectedComics.clear();
                            });
                          }
                        });
                      },
                    ),
                    ...exportActions([c as LocalComic]),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      canPop: !multiSelectMode && !searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        } else if (searchMode) {
          setState(() {
            searchMode = false;
            keyword = "";
            update();
          });
        }
      },
      child: body,
    );
  }

  Future<bool> deleteComics(List<LocalComic> comics) async {
    bool isDeleted = false;
    await showDialog(
      context: context,
      builder: (context) {
        bool removeComicFile = true;
        bool removeFavoriteAndHistory = true;
        return StatefulBuilder(
          builder: (context, state) {
            return ContentDialog(
              title: "Delete".tl,
              content: Column(
                children: [
                  CheckboxListTile(
                    title: Text("Remove local favorite and history".tl),
                    value: removeFavoriteAndHistory,
                    onChanged: (v) {
                      state(() {
                        removeFavoriteAndHistory = !removeFavoriteAndHistory;
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: Text("Also remove files on disk".tl),
                    value: removeComicFile,
                    onChanged: (v) {
                      state(() {
                        removeComicFile = !removeComicFile;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                if (comics.length == 1 && comics.first.hasChapters)
                  TextButton(
                    child: Text("Delete Chapters".tl),
                    onPressed: () {
                      context.pop();
                      showDeleteChaptersPopWindow(context, comics.first);
                    },
                  ),
                FilledButton(
                  onPressed: () {
                    context.pop();
                    _gateway.batchDeleteComics(
                      comics,
                      removeComicFile,
                      removeFavoriteAndHistory,
                    );
                    isDeleted = true;
                  },
                  child: Text("Confirm".tl),
                ),
              ],
            );
          },
        );
      },
    );
    return isDeleted;
  }

  List<MenuEntry> exportActions(List<LocalComic> comics) {
    return [
      MenuEntry(
        icon: Icons.outbox_outlined,
        text: "Export as cbz".tl,
        onClick: () {
          exportComics(comics, CBZ.export, ".cbz");
        },
      ),
      MenuEntry(
        icon: Icons.picture_as_pdf_outlined,
        text: "Export as pdf".tl,
        onClick: () async {
          exportComics(comics, (comic, outFilePath) {
            return createPdfFromComicIsolate(
              comic,
              outFilePath,
              resolvedComicDirectory: comic.baseDir,
            );
          }, ".pdf");
        },
      ),
      MenuEntry(
        icon: Icons.import_contacts_outlined,
        text: "Export as epub".tl,
        onClick: () async {
          exportComics(comics, createEpubWithLocalComic, ".epub");
        },
      ),
    ];
  }

  /// Export given comics to a file
  void exportComics(
    List<LocalComic> comics,
    ExportComicFunc export,
    String ext,
  ) async {
    var current = 0;
    var cacheDir = FilePath.join(App.cachePath, 'comics_export');
    var outFile = FilePath.join(App.cachePath, 'comics_export.zip');
    bool canceled = false;
    if (Directory(cacheDir).existsSync()) {
      Directory(cacheDir).deleteSync(recursive: true);
    }
    Directory(cacheDir).createSync();
    var loadingController = showLoadingDialog(
      context,
      allowCancel: true,
      message: "${"Exporting".tl} $current/${comics.length}",
      withProgress: comics.length > 1,
      onCancel: () {
        canceled = true;
      },
    );
    try {
      var fileName = "";
      // For each comic, export it to a file
      for (var comic in comics) {
        fileName = FilePath.join(
          cacheDir,
          sanitizeFileName(comic.title, maxLength: 100) + ext,
        );
        await export(comic, fileName);
        current++;
        if (comics.length > 1) {
          loadingController.setMessage(
            "${"Exporting".tl} $current/${comics.length}",
          );
          loadingController.setProgress(current / comics.length);
        }
        if (canceled) {
          return;
        }
      }
      // For single comic, just save the file
      if (comics.length == 1) {
        await saveFile(file: File(fileName), filename: File(fileName).name);
        Directory(cacheDir).deleteSync(recursive: true);
        loadingController.close();
        return;
      }
      // For multiple comics, compress the folder
      loadingController.setProgress(null);
      loadingController.setMessage("Compressing".tl);
      await ZipFile.compressFolderAsync(cacheDir, outFile);
      if (canceled) {
        File(outFile).deleteIgnoreError();
        return;
      }
    } catch (e, s) {
      AppDiagnostics.error(
        'ui.local_comics',
        e,
        stackTrace: s,
        message: 'export_comics_failed',
      );
      context.showMessage(message: e.toString());
      loadingController.close();
      return;
    } finally {
      Directory(cacheDir).deleteIgnoreError(recursive: true);
    }
    await saveFile(file: File(outFile), filename: "comics_export.zip");
    loadingController.close();
    File(outFile).deleteIgnoreError();
  }
}

typedef ExportComicFunc =
    Future<File> Function(LocalComic comic, String outFilePath);

/// Opens the folder containing the comic in the system file explorer
Future<void> openComicFolder(BuildContext context, LocalComic comic) async {
  try {
    final folderPath = comic.baseDir;

    if (App.isWindows) {
      await Process.run('explorer', [folderPath]);
    } else if (App.isMacOS) {
      await Process.run('open', [folderPath]);
    } else if (App.isLinux) {
      // Try different file managers commonly found on Linux
      try {
        await Process.run('xdg-open', [folderPath]);
      } catch (e) {
        // Fallback to other common file managers
        try {
          await Process.run('nautilus', [folderPath]);
        } catch (e) {
          try {
            await Process.run('dolphin', [folderPath]);
          } catch (e) {
            try {
              await Process.run('thunar', [folderPath]);
            } catch (e) {
              // Last resort: use the URL launcher with file:// protocol
              await launchUrlString('file://$folderPath');
            }
          }
        }
      }
    } else {
      // For mobile platforms, use the URL launcher with file:// protocol
      await launchUrlString('file://$folderPath');
    }
  } catch (e, s) {
    AppDiagnostics.error(
      'ui.local_comics',
      e,
      stackTrace: s,
      message: 'open_comic_folder_failed',
    );
    if (context.mounted) {
      context.showMessage(message: "Failed to open folder: $e");
    }
  }
}

void showDeleteChaptersPopWindow(BuildContext context, LocalComic comic) {
  final gateway = _LocalComicsGateway();
  var chapters = <String>[];

  showPopUpWidget(
    context,
    PopUpWidgetScaffold(
      title: "Delete Chapters".tl,
      body: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: comic.downloadedChapters.length,
                  itemBuilder: (context, index) {
                    var id = comic.downloadedChapters[index];
                    var chapter = comic.chapters![id] ?? "Unknown Chapter";
                    return CheckboxListTile(
                      title: Text(chapter),
                      value: chapters.contains(id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            chapters.add(id);
                          } else {
                            chapters.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: () {
                        Future.delayed(const Duration(milliseconds: 200), () {
                          gateway.deleteChapters(comic, chapters);
                        });
                        context.pop();
                      },
                      child: Text("Submit".tl),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

void showManageChaptersDialog(BuildContext context, LocalComic comic) {
  showSideBar(
    context,
    _LocalComicManagePanel(
      comic: comic,
      initialTab: _LocalComicManageTab.chapters,
    ),
    width: 760,
    addTopPadding: true,
  );
}

void showReorderPagesDialog(BuildContext context, LocalComic comic) {
  showSideBar(
    context,
    _LocalComicManagePanel(
      comic: comic,
      initialTab: _LocalComicManageTab.pages,
    ),
    width: 760,
    addTopPadding: true,
  );
}

void showSetCoverDialog(BuildContext context, LocalComic comic) {
  showSideBar(
    context,
    _LocalComicManagePanel(
      comic: comic,
      initialTab: _LocalComicManageTab.cover,
    ),
    width: 760,
    addTopPadding: true,
  );
}

void showMergeComicsAsChaptersDialog(BuildContext context, LocalComic comic) {
  showSideBar(
    context,
    _LocalComicManagePanel(
      comic: comic,
      initialTab: _LocalComicManageTab.merge,
    ),
    width: 760,
    addTopPadding: true,
  );
}

enum _LocalComicManageTab { chapters, pages, cover, merge }

class _LocalComicManagePanel extends StatefulWidget {
  const _LocalComicManagePanel({required this.comic, required this.initialTab});

  final LocalComic comic;
  final _LocalComicManageTab initialTab;

  @override
  State<_LocalComicManagePanel> createState() => _LocalComicManagePanelState();
}

class _LocalComicManagePanelState extends State<_LocalComicManagePanel>
    with SingleTickerProviderStateMixin {
  final _gateway = _LocalComicsGateway();

  late TabController _tabController;
  LocalComic? current;
  bool loading = true;
  bool saving = false;
  String chapterQuery = "";

  String? selectedChapterForPages;
  String? selectedChapterForCover;
  List<String> pageOrder = [];
  List<String> loadedPageOrder = [];
  List<String> coverPagePaths = [];
  String? selectedCoverPage;

  bool get hasPageOrderDraft {
    if (pageOrder.length != loadedPageOrder.length) {
      return true;
    }
    for (int i = 0; i < pageOrder.length; i++) {
      if (pageOrder[i] != loadedPageOrder[i]) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<String> get _chapterIds => current?.downloadedChapters ?? const [];

  List<String> get _filteredChapterIds {
    if (chapterQuery.trim().isEmpty) {
      return _chapterIds;
    }
    final q = chapterQuery.trim().toLowerCase();
    return _chapterIds.where((id) {
      final title = _chapterTitle(id).toLowerCase();
      return title.contains(q) || id.toLowerCase().contains(q);
    }).toList();
  }

  String _chapterTitle(String id) {
    return current?.chapters?.allChapters[id] ?? "Unknown Chapter";
  }

  String _chapterLabelAt(List<String> ids, int index) {
    final id = ids[index];
    return formatLocalChapterDisplayLabel(
      index: index,
      title: _chapterTitle(id),
    );
  }

  List<String> _chapterLabels(List<String> ids) {
    return [
      for (final entry in ids.indexed)
        formatLocalChapterDisplayLabel(
          index: entry.$1,
          title: _chapterTitle(entry.$2),
        ),
    ];
  }

  String? _selectedChapterLabel(String? selectedChapterId, List<String> ids) {
    if (selectedChapterId == null) {
      return null;
    }
    final index = ids.indexOf(selectedChapterId);
    if (index < 0) {
      return null;
    }
    return _chapterLabelAt(ids, index);
  }

  Future<void> _reload() async {
    final refreshed = await _gateway.findComic(
      widget.comic.id,
      widget.comic.comicType,
    );
    if (!mounted) return;
    current = refreshed;
    if (current != null && current!.hasChapters) {
      if (current!.downloadedChapters.isNotEmpty) {
        selectedChapterForPages ??= current!.downloadedChapters.first;
        selectedChapterForCover ??= current!.downloadedChapters.first;
      }
    }
    await Future.wait([_loadPagesForReorder(), _loadPagesForCover()]);
    if (!mounted) return;
    setState(() {
      loading = false;
    });
  }

  Future<void> _loadPagesForReorder() async {
    final comic = current;
    if (comic == null) return;
    if (comic.hasChapters && selectedChapterForPages == null) {
      pageOrder = [];
      loadedPageOrder = [];
      return;
    }
    final ep = resolveLocalChapterPageTarget(
      hasChapters: comic.hasChapters,
      selectedChapterId: selectedChapterForPages,
    );
    final images = await _gateway.loadImages(comic.id, comic.comicType, ep);
    pageOrder = images
        .map((e) => File(localImageUriToPath(e)).name)
        .toList(growable: true);
    loadedPageOrder = List<String>.from(pageOrder);
  }

  Future<void> _loadPagesForCover() async {
    final comic = current;
    if (comic == null) return;
    if (comic.hasChapters && selectedChapterForCover == null) {
      coverPagePaths = [];
      selectedCoverPage = null;
      return;
    }
    final ep = resolveLocalChapterPageTarget(
      hasChapters: comic.hasChapters,
      selectedChapterId: selectedChapterForCover,
    );
    coverPagePaths = await _gateway.loadImages(comic.id, comic.comicType, ep);
    selectedCoverPage = coverPagePaths.isEmpty ? null : coverPagePaths.first;
  }

  Future<void> _renameChapter(String id) async {
    final controller = TextEditingController(text: _chapterTitle(id));
    String? newName;
    await showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: "Rename Chapter".tl,
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: "Chapter title".tl),
        ),
        actions: [
          TextButton(onPressed: context.pop, child: Text("Cancel".tl)),
          FilledButton(
            onPressed: () {
              newName = controller.text.trim();
              context.pop();
            },
            child: Text("Save".tl),
          ),
        ],
      ),
    );
    final comic = current;
    if (comic == null || newName == null || newName!.isEmpty) return;
    _gateway.renameChapter(comic, id, newName!);
    await _reload();
    if (mounted) setState(() {});
  }

  Future<void> _deleteChapter(String id) async {
    final comic = current;
    if (comic == null) return;
    bool confirm = false;
    await showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: "Delete Chapter".tl,
        content: Text(
          "Delete chapter '@a'?".tlParams({"a": _chapterTitle(id)}),
        ).paddingHorizontal(16).paddingVertical(8),
        actions: [
          TextButton(onPressed: context.pop, child: Text("Cancel".tl)),
          FilledButton(
            onPressed: () {
              confirm = true;
              context.pop();
            },
            child: Text("Delete".tl),
          ),
        ],
      ),
    );
    if (!confirm) return;
    _gateway.deleteChapters(comic, [id]);
    await _reload();
    if (mounted) context.showMessage(message: "Deleted".tl);
  }

  Future<void> _savePageOrder() async {
    final comic = current;
    if (comic == null) return;
    if (!canReorderLocalComicPages(
      comicBaseDir: comic.baseDir,
      localRootPath: _gateway.localRootPath,
    )) {
      context.showMessage(
        message: "Only app-managed local comics support page reorder".tl,
      );
      return;
    }
    setState(() {
      saving = true;
    });
    try {
      final ep = resolveLocalChapterPageTarget(
        hasChapters: comic.hasChapters,
        selectedChapterId: selectedChapterForPages,
      );
      await _gateway.reorderPages(comic, ep, pageOrder);
      loadedPageOrder = List<String>.from(pageOrder);
      if (mounted) context.showMessage(message: "Saved".tl);
    } catch (e) {
      if (mounted) context.showMessage(message: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  Future<void> _saveCover() async {
    final comic = current;
    if (comic == null || selectedCoverPage == null) return;
    setState(() {
      saving = true;
    });
    try {
      await _gateway.setCover(comic, localImageUriToPath(selectedCoverPage!));
      if (mounted) context.showMessage(message: "Saved".tl);
    } catch (e) {
      if (mounted) context.showMessage(message: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  Future<void> _addComicsAsChapters() async {
    if (saving) return;
    final comic = current;
    if (comic == null) return;
    final all = await _gateway.getComics(LocalSortType.name);
    final candidates = buildChapterMergeCandidates(
      targetComic: comic,
      allComics: all,
    );
    if (candidates.isEmpty) {
      context.showMessage(message: "No other local comics found".tl);
      return;
    }
    final selected = <LocalComic>{};
    var deleteSource = false;
    bool submit = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInnerState) => ContentDialog(
          title: "Add Comics as Chapters".tl,
          content: SizedBox(
            width: 560,
            height: 460,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final source = candidates[index];
                      return CheckboxListTile(
                        value: selected.contains(source),
                        title: Text(source.title),
                        subtitle: Text(
                          source.hasChapters
                              ? "${source.downloadedChapters.length} ${"Chapters".tl.toLowerCase()}"
                              : "Single chapter".tl,
                        ),
                        onChanged: (v) {
                          setInnerState(() {
                            if (v == true) {
                              selected.add(source);
                            } else {
                              selected.remove(source);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text("Selected: ${selected.length}".tl),
                  ),
                ),
                CheckboxListTile(
                  value: deleteSource,
                  onChanged: (v) {
                    setInnerState(() {
                      deleteSource = v ?? false;
                    });
                  },
                  title: Text("Delete source comics after merge".tl),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: context.pop, child: Text("Cancel".tl)),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      submit = true;
                      context.pop();
                    },
              child: Text("Add".tl),
            ),
          ],
        ),
      ),
    );
    if (!submit || selected.isEmpty) return;
    setState(() {
      saving = true;
    });
    try {
      await _gateway.addComicsAsChapters(
        comic,
        selected.toList(),
        deleteSourceComics: deleteSource,
      );
      await _reload();
      if (mounted) context.showMessage(message: "Saved".tl);
    } catch (e) {
      if (mounted) context.showMessage(message: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  Widget _buildChaptersTab() {
    final ids = _filteredChapterIds;
    final canReorder = chapterQuery.trim().isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: "Search chapters".tl,
                  ),
                  onChanged: (v) {
                    setState(() {
                      chapterQuery = v;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Text("${_chapterIds.length} ${"Chapters".tl}"),
            ],
          ),
        ),
        if (!canReorder)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Clear search to reorder chapters".tl,
                style: ts.s12.copyWith(color: context.colorScheme.outline),
              ),
            ),
          ),
        Expanded(
          child: ids.isEmpty
              ? Center(child: Text("No chapters".tl))
              : ReorderableListView.builder(
                  itemCount: ids.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (!canReorder) {
                      if (mounted) {
                        context.showMessage(
                          message: "Clear search to reorder chapters".tl,
                        );
                      }
                      return;
                    }
                    final comic = current;
                    if (comic == null) return;
                    final reordered = reorderChapterIds(
                      chapterIds: _chapterIds,
                      oldIndex: oldIndex,
                      newIndex: newIndex,
                    );
                    try {
                      _gateway.reorderChapters(comic, reordered);
                      await _reload();
                      if (mounted) setState(() {});
                    } catch (e) {
                      if (mounted) context.showMessage(message: e.toString());
                    }
                  },
                  itemBuilder: (context, index) {
                    final id = ids[index];
                    return ListTile(
                      key: ValueKey(id),
                      title: Text(
                        formatLocalChapterDisplayLabel(
                          index: index,
                          title: _chapterTitle(id),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: "Rename".tl,
                            onPressed: () => _renameChapter(id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: "Delete".tl,
                            onPressed: () => _deleteChapter(id),
                          ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPagesTab() {
    final comic = current;
    return Column(
      children: [
        if (comic != null && comic.hasChapters)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text("Chapter".tl),
            trailing: Select(
              current: _selectedChapterLabel(
                selectedChapterForPages,
                comic.downloadedChapters,
              ),
              values: _chapterLabels(comic.downloadedChapters),
              minWidth: 220,
              onTap: (index) async {
                if (saving) {
                  return;
                }
                selectedChapterForPages = comic.downloadedChapters[index];
                await _loadPagesForReorder();
                if (mounted) setState(() {});
              },
            ),
          ),
        Expanded(
          child: AbsorbPointer(
            absorbing: saving,
            child: pageOrder.isEmpty
                ? Center(child: Text("No pages".tl))
                : ReorderableListView.builder(
                    itemCount: pageOrder.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final moved = pageOrder.removeAt(oldIndex);
                        pageOrder.insert(newIndex, moved);
                      });
                    },
                    itemBuilder: (context, index) {
                      final page = pageOrder[index];
                      return ListTile(
                        key: ValueKey(page),
                        title: Text("${index + 1}. $page"),
                        trailing: const Icon(Icons.drag_handle),
                      );
                    },
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!hasPageOrderDraft)
                Text(
                  "No changes".tl,
                  style: ts.s12.copyWith(color: context.colorScheme.outline),
                ).paddingRight(12),
              FilledButton(
                onPressed: saving || !hasPageOrderDraft ? null : _savePageOrder,
                child: Text("Save".tl),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverTab() {
    final comic = current;
    return Column(
      children: [
        if (comic != null && comic.hasChapters)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text("Chapter".tl),
            trailing: Select(
              current: _selectedChapterLabel(
                selectedChapterForCover,
                comic.downloadedChapters,
              ),
              values: _chapterLabels(comic.downloadedChapters),
              minWidth: 220,
              onTap: (index) async {
                if (saving) {
                  return;
                }
                selectedChapterForCover = comic.downloadedChapters[index];
                await _loadPagesForCover();
                if (mounted) setState(() {});
              },
            ),
          ),
        Expanded(
          child: AbsorbPointer(
            absorbing: saving,
            child: coverPagePaths.isEmpty
                ? Center(child: Text("No pages".tl))
                : RadioGroup<String>(
                    groupValue: selectedCoverPage,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        selectedCoverPage = v;
                      });
                    },
                    child: ListView.builder(
                      itemCount: coverPagePaths.length,
                      itemBuilder: (context, index) {
                        final path = coverPagePaths[index];
                        final filePath = path.replaceFirst("file://", "");
                        final name = File(filePath).name;
                        return ListTile(
                          onTap: saving
                              ? null
                              : () {
                                  setState(() {
                                    selectedCoverPage = path;
                                  });
                                },
                          leading: Radio<String>(value: path),
                          title: Text("${index + 1}. $name"),
                        );
                      },
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: saving || selectedCoverPage == null
                    ? null
                    : _saveCover,
                child: Text("Save".tl),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMergeTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Merge local comics into chapters".tl, style: ts.s16),
          const SizedBox(height: 8),
          Text(
            "Choose local comics and append them as chapters to this comic".tl,
            style: ts.s12.copyWith(color: context.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: saving ? null : _addComicsAsChapters,
            icon: const Icon(Icons.playlist_add),
            label: Text("Add Comics as Chapters".tl),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text("Manage Chapters".tl)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : current == null
          ? Center(child: Text("Comic not found".tl))
          : Column(
              children: [
                AppTabBar(
                  withUnderLine: false,
                  controller: _tabController,
                  tabs: [
                    Tab(text: "Chapters".tl),
                    Tab(text: "Reorder Pages".tl),
                    Tab(text: "Set Cover".tl),
                    Tab(text: "Merge".tl),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildChaptersTab(),
                      _buildPagesTab(),
                      _buildCoverTab(),
                      _buildMergeTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
