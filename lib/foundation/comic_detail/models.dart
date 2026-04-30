import 'package:venera/foundation/source_ref.dart';

enum LibraryState {
  localOnly,
  remoteOnly,
  localWithRemoteSource,
  downloaded,
  unavailable,
}

enum SourcePlatformKind { local, remote, virtual }

enum SourceAliasType {
  canonical,
  legacyKey,
  legacyType,
  pluginKey,
  displayName,
  migration,
  unknown,
}

enum ReaderTabLoadMode { localLibrary, remoteSource, cache, unavailable }

enum PageOrderKind {
  sourceDefault,
  userCustom,
  importedFolder,
  temporarySession,
}

class SourcePlatformRef {
  final String platformId;
  final String canonicalKey;
  final String displayName;
  final SourcePlatformKind kind;
  final String matchedAlias;
  final SourceAliasType matchedAliasType;
  final int? legacyIntType;

  const SourcePlatformRef({
    required this.platformId,
    required this.canonicalKey,
    required this.displayName,
    required this.kind,
    required this.matchedAlias,
    required this.matchedAliasType,
    this.legacyIntType,
  });
}

class ComicTagVm {
  final String id;
  final String name;
  final String? color;

  const ComicTagVm({required this.id, required this.name, this.color});
}

class SourceTagVm {
  final String id;
  final String name;
  final String namespace;
  final SourcePlatformRef platform;

  const SourceTagVm({
    required this.id,
    required this.name,
    required this.namespace,
    required this.platform,
  });
}

class ChapterVm {
  final String chapterId;
  final String title;
  final double? chapterNo;
  final int pageCount;
  final bool hasCustomPageOrder;
  final DateTime? lastReadAt;

  const ChapterVm({
    required this.chapterId,
    required this.title,
    this.chapterNo,
    this.pageCount = 0,
    this.hasCustomPageOrder = false,
    this.lastReadAt,
  });
}

class ReaderTabVm {
  final String tabId;
  final String? title;
  final String? currentChapterId;
  final int currentPageIndex;
  final SourceRef sourceRef;
  final ReaderTabLoadMode loadMode;
  final String? pageOrderId;
  final bool isActive;
  final DateTime? updatedAt;

  const ReaderTabVm({
    required this.tabId,
    this.title,
    this.currentChapterId,
    this.currentPageIndex = 0,
    required this.sourceRef,
    required this.loadMode,
    this.pageOrderId,
    this.isActive = false,
    this.updatedAt,
  });
}

class PageOrderSummaryVm {
  final String? activeOrderId;
  final PageOrderKind? activeOrderType;
  final int totalOrders;
  final int totalPageCount;
  final int visiblePageCount;

  const PageOrderSummaryVm({
    this.activeOrderId,
    this.activeOrderType,
    this.totalOrders = 0,
    this.totalPageCount = 0,
    this.visiblePageCount = 0,
  });

  static const empty = PageOrderSummaryVm();

  bool get hasCustomOrder => activeOrderType == PageOrderKind.userCustom;
}

class ComicSourceCitation {
  final SourcePlatformRef platform;
  final String relationType;
  final String? comicUrl;
  final String? chapterUrl;
  final String? imageUrl;
  final String? sourceTitle;
  final DateTime? downloadedAt;
  final DateTime? lastVerifiedAt;

  const ComicSourceCitation({
    required this.platform,
    required this.relationType,
    this.comicUrl,
    this.chapterUrl,
    this.imageUrl,
    this.sourceTitle,
    this.downloadedAt,
    this.lastVerifiedAt,
  });

  String get platformName => platform.displayName;
}

class ComicDetailActions {
  final bool canContinueReading;
  final bool canStartReading;
  final bool canOpenInNewTab;
  final bool canFavorite;
  final bool canManageUserTags;
  final bool canViewSource;
  final bool canManagePageOrder;
  final bool canSearchRelatedRemote;
  final bool canLinkRemoteSource;

  const ComicDetailActions({
    this.canContinueReading = false,
    this.canStartReading = false,
    this.canOpenInNewTab = false,
    this.canFavorite = false,
    this.canManageUserTags = false,
    this.canViewSource = false,
    this.canManagePageOrder = false,
    this.canSearchRelatedRemote = false,
    this.canLinkRemoteSource = false,
  });

  static const none = ComicDetailActions();

  bool get hasAnyAction =>
      canContinueReading ||
      canStartReading ||
      canOpenInNewTab ||
      canFavorite ||
      canManageUserTags ||
      canViewSource ||
      canManagePageOrder ||
      canSearchRelatedRemote ||
      canLinkRemoteSource;
}

class ComicDetailViewModel {
  final String comicId;
  final String title;
  final String? coverLocalPath;
  final LibraryState libraryState;
  final ComicSourceCitation? primarySource;
  final List<ComicTagVm> userTags;
  final List<SourceTagVm> sourceTags;
  final List<ChapterVm> chapters;
  final List<ReaderTabVm> readerTabs;
  final PageOrderSummaryVm pageOrderSummary;
  final ComicDetailActions availableActions;
  final DateTime? updatedAt;

  ComicDetailViewModel({
    required this.comicId,
    required this.title,
    this.coverLocalPath,
    required this.libraryState,
    this.primarySource,
    List<ComicTagVm> userTags = const <ComicTagVm>[],
    List<SourceTagVm> sourceTags = const <SourceTagVm>[],
    List<ChapterVm> chapters = const <ChapterVm>[],
    List<ReaderTabVm> readerTabs = const <ReaderTabVm>[],
    this.pageOrderSummary = PageOrderSummaryVm.empty,
    this.availableActions = ComicDetailActions.none,
    this.updatedAt,
  }) : userTags = List.unmodifiable(userTags),
       sourceTags = List.unmodifiable(sourceTags),
       chapters = List.unmodifiable(chapters),
       readerTabs = List.unmodifiable(readerTabs);

  factory ComicDetailViewModel.scaffold({
    required String comicId,
    required String title,
    required LibraryState libraryState,
    String? coverLocalPath,
    ComicSourceCitation? primarySource,
    ComicDetailActions availableActions = ComicDetailActions.none,
    DateTime? updatedAt,
  }) {
    return ComicDetailViewModel(
      comicId: comicId,
      title: title,
      coverLocalPath: coverLocalPath,
      libraryState: libraryState,
      primarySource: primarySource,
      availableActions: availableActions,
      updatedAt: updatedAt,
    );
  }

  bool get isReadable =>
      availableActions.canContinueReading ||
      availableActions.canStartReading ||
      availableActions.canOpenInNewTab;
}
