import 'package:venera/foundation/db/unified_comics_store.dart';

import 'models.dart';

typedef ComicDetailLoader =
    Future<ComicDetailViewModel?> Function(String comicId);

abstract class ComicDetailRepository {
  Future<ComicDetailViewModel?> getComicDetail(String comicId);
}

class StaticComicDetailRepository implements ComicDetailRepository {
  const StaticComicDetailRepository(this.records);

  final Map<String, ComicDetailViewModel> records;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    return records[comicId];
  }
}

class CompositeComicDetailRepository implements ComicDetailRepository {
  const CompositeComicDetailRepository({required this.loaders});

  final List<ComicDetailLoader> loaders;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    for (final loader in loaders) {
      final detail = await loader(comicId);
      if (detail != null) {
        return detail;
      }
    }
    return null;
  }
}

class StubComicDetailRepository implements ComicDetailRepository {
  const StubComicDetailRepository({
    this.missingState = LibraryState.unavailable,
  });

  final LibraryState missingState;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    return ComicDetailViewModel.scaffold(
      comicId: comicId,
      title: comicId,
      libraryState: missingState,
    );
  }
}

class UnifiedLocalComicDetailRepository implements ComicDetailRepository {
  const UnifiedLocalComicDetailRepository({required this.store});

  final UnifiedComicsStore store;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    final snapshot = await store.loadComicSnapshot(comicId);
    if (snapshot == null || snapshot.localLibraryItems.isEmpty) {
      return null;
    }

    final chapters = <ChapterVm>[];
    for (final chapter in snapshot.chapters) {
      chapters.add(
        ChapterVm(
          chapterId: chapter.id,
          title: chapter.title,
          chapterNo: chapter.chapterNo,
          pageCount: await store.countPagesForChapter(chapter.id),
        ),
      );
    }

    final summary = await store.loadPageOrderSummary(comicId);
    return ComicDetailViewModel(
      comicId: snapshot.comic.id,
      title: snapshot.comic.title,
      coverLocalPath: snapshot.comic.coverLocalPath,
      libraryState: LibraryState.localOnly,
      chapters: chapters,
      pageOrderSummary: PageOrderSummaryVm(
        activeOrderId: summary.activeOrderId,
        activeOrderType: _mapPageOrderKind(summary.activeOrderType),
        totalOrders: summary.totalOrders,
        totalPageCount: summary.totalPageCount,
        visiblePageCount: summary.visiblePageCount,
      ),
      availableActions: const ComicDetailActions(
        canContinueReading: true,
        canStartReading: true,
        canOpenInNewTab: true,
        canFavorite: true,
        canManageUserTags: true,
        canManagePageOrder: true,
        canSearchRelatedRemote: true,
        canLinkRemoteSource: true,
      ),
    );
  }
}

PageOrderKind? _mapPageOrderKind(String? orderType) {
  switch (orderType) {
    case 'source_default':
      return PageOrderKind.sourceDefault;
    case 'user_custom':
      return PageOrderKind.userCustom;
    case 'imported_folder':
      return PageOrderKind.importedFolder;
    case 'temporary_session':
      return PageOrderKind.temporarySession;
    default:
      return null;
  }
}
