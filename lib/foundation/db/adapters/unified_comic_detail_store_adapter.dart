import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/comic_detail_store_port.dart';
import 'package:venera/foundation/ports/reader_session_store_port.dart';

class UnifiedComicDetailStoreAdapter
    implements ComicDetailStorePort, ReaderSessionStorePort {
  const UnifiedComicDetailStoreAdapter(this.store);

  final UnifiedComicsStore store;

  @override
  Future<int> countPagesForChapter(String chapterId) {
    return store.countPagesForChapter(chapterId);
  }

  @override
  Future<HistoryEventRecord?> loadLatestHistoryEvent(String comicId) {
    return store.loadLatestHistoryEvent(comicId);
  }

  @override
  Future<ComicSourceLinkRecord?> loadPrimaryComicSourceLink(String comicId) {
    return store.loadPrimaryComicSourceLink(comicId);
  }

  @override
  Future<SourcePlatformRecord?> loadSourcePlatformById(String platformId) {
    return store.loadSourcePlatformById(platformId);
  }

  @override
  Future<List<SourceTagRecord>> loadSourceTagsForComicSourceLink(
    String comicSourceLinkId,
  ) {
    return store.loadSourceTagsForComicSourceLink(comicSourceLinkId);
  }

  @override
  Future<List<UserTagRecord>> loadUserTagsForComic(String comicId) {
    return store.loadUserTagsForComic(comicId);
  }

  @override
  Future<PageOrderSummaryRecord> loadPageOrderSummary(String comicId) {
    return store.loadPageOrderSummary(comicId);
  }

  @override
  Future<UnifiedComicSnapshot?> loadComicSnapshot(String comicId) {
    return store.loadComicSnapshot(comicId);
  }

  @override
  Future<List<PageRecord>> loadActivePageOrderPages(String chapterId) {
    return store.loadActivePageOrderPages(chapterId);
  }

  @override
  Future<PageOrderRecord?> loadActivePageOrderForChapter(String chapterId) {
    return store.loadActivePageOrderForChapter(chapterId);
  }

  @override
  Future<void> upsertUserTag(UserTagRecord record) {
    return store.upsertUserTag(record);
  }

  @override
  Future<void> attachUserTagToComic(ComicUserTagRecord record) {
    return store.attachUserTagToComic(record);
  }

  @override
  Future<void> removeUserTagFromComic({
    required String comicId,
    required String userTagId,
  }) {
    return store.removeUserTagFromComic(comicId: comicId, userTagId: userTagId);
  }

  @override
  Future<String> syncRemoteComic(ComicDetails detail) {
    return RemoteComicCanonicalSyncService(store: store).syncComic(detail);
  }

  @override
  Future<void> syncRemoteChapterPages({
    required String sourceKey,
    required String comicId,
    required String chapterId,
    required List<String> pageKeys,
  }) {
    return RemoteComicCanonicalSyncService(store: store).syncChapterPages(
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      pageKeys: pageKeys,
    );
  }

  @override
  Future<void> deleteReaderSession(String sessionId) {
    return store.deleteReaderSession(sessionId);
  }

  @override
  Future<ReaderSessionRecord?> loadReaderSessionByComic(String comicId) {
    return store.loadReaderSessionByComic(comicId);
  }

  @override
  Future<List<ReaderTabRecord>> loadReaderTabsForSession(String sessionId) {
    return store.loadReaderTabsForSession(sessionId);
  }

  @override
  Future<void> setReaderSessionActiveTab({
    required String sessionId,
    required String activeTabId,
  }) {
    return store.setReaderSessionActiveTab(
      sessionId: sessionId,
      activeTabId: activeTabId,
    );
  }

  @override
  Future<void> upsertReaderSession(ReaderSessionRecord record) {
    return store.upsertReaderSession(record);
  }

  @override
  Future<void> upsertReaderTab(ReaderTabRecord record) {
    return store.upsertReaderTab(record);
  }
}
