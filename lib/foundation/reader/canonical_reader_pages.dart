import 'package:venera/foundation/db/store_records.dart'
    show UnifiedComicSnapshot;
import 'package:venera/foundation/ports/comic_detail_store_port.dart';

class CanonicalReaderPages {
  const CanonicalReaderPages({required this.store});

  final ComicDetailStorePort store;

  Future<List<String>> loadLocalPages({
    required String localComicId,
    String? chapterId,
  }) async {
    final snapshot = await store.loadComicSnapshot(localComicId);
    if (snapshot == null || snapshot.localLibraryItems.isEmpty) {
      throw StateError('CANONICAL_LOCAL_COMIC_NOT_FOUND:$localComicId');
    }

    final targetChapterId = chapterId ?? _firstChapterId(snapshot);
    if (targetChapterId == null) {
      throw StateError('CANONICAL_CHAPTER_NOT_FOUND:$localComicId');
    }

    final pages = await store.loadActivePageOrderPages(targetChapterId);
    if (pages.isEmpty) {
      throw StateError('CANONICAL_PAGE_ORDER_NOT_FOUND:$targetChapterId');
    }

    return pages.map((page) => Uri.file(page.localPath).toString()).toList();
  }

  Future<List<String>> loadRemotePages({
    required String canonicalComicId,
    required String chapterId,
  }) async {
    final snapshot = await store.loadComicSnapshot(canonicalComicId);
    if (snapshot == null) {
      throw StateError('CANONICAL_REMOTE_COMIC_NOT_FOUND:$canonicalComicId');
    }

    final canonicalChapterId = '$canonicalComicId:$chapterId';
    final chapterExists = snapshot.chapters.any(
      (chapter) => chapter.id == canonicalChapterId,
    );
    if (!chapterExists) {
      throw StateError(
        'CANONICAL_REMOTE_CHAPTER_NOT_FOUND:$canonicalChapterId',
      );
    }

    final pages = await store.loadActivePageOrderPages(canonicalChapterId);
    if (pages.isEmpty) {
      throw StateError(
        'CANONICAL_REMOTE_PAGE_ORDER_NOT_FOUND:$canonicalChapterId',
      );
    }

    return pages.map((page) => page.localPath).toList();
  }

  String? _firstChapterId(UnifiedComicSnapshot snapshot) {
    if (snapshot.chapters.isEmpty) {
      return null;
    }
    return snapshot.chapters.first.id;
  }
}
