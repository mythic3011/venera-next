import 'package:venera/foundation/ports/comic_detail_store_port.dart';
import 'package:venera/foundation/ports/local_library_browse_store_port.dart';

class ReaderDebugSnapshot {
  const ReaderDebugSnapshot({
    required this.generatedAt,
    required this.comicId,
    required this.loadMode,
    required this.controllerLifecycle,
    required this.linkStatus,
    this.localLibraryItemId,
    this.comicSourceId,
    this.sourcePlatformId,
    this.sourceComicId,
    this.readerTabId,
    this.pageOrderId,
    this.chapterId,
  });

  final DateTime generatedAt;
  final String comicId;
  final String loadMode;
  final String controllerLifecycle;
  final String linkStatus;
  final String? localLibraryItemId;
  final String? comicSourceId;
  final String? sourcePlatformId;
  final String? sourceComicId;
  final String? readerTabId;
  final String? pageOrderId;
  final String? chapterId;

  Map<String, Object?> toJson() {
    return {
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'comicId': comicId,
      'localLibraryItemId': localLibraryItemId,
      'comicSourceId': comicSourceId,
      'sourcePlatformId': sourcePlatformId,
      'sourceComicId': sourceComicId,
      'linkStatus': linkStatus,
      'readerTabId': readerTabId,
      'pageOrderId': pageOrderId,
      'chapterId': chapterId,
      'loadMode': loadMode,
      'controllerLifecycle': controllerLifecycle,
    };
  }
}

class ReaderDebugSnapshotService {
  const ReaderDebugSnapshotService({
    required this.localLibraryStore,
    required this.comicDetailStore,
  });

  final LocalLibraryBrowseStorePort localLibraryStore;
  final ComicDetailStorePort comicDetailStore;

  Future<ReaderDebugSnapshot> build({
    required String comicId,
    required String loadMode,
    required String controllerLifecycle,
    String? chapterId,
  }) async {
    final isLocal = loadMode == 'local';
    final localItem = isLocal
        ? await localLibraryStore.loadPrimaryLocalLibraryItem(comicId)
        : null;
    if (isLocal && localItem == null) {
      throw StateError('CANONICAL_LOCAL_COMIC_NOT_FOUND:$comicId');
    }

    final pageOrder = chapterId == null
        ? null
        : await comicDetailStore.loadActivePageOrderForChapter(chapterId);
    if (isLocal && chapterId != null && pageOrder == null) {
      throw StateError('CANONICAL_PAGE_ORDER_NOT_FOUND:$chapterId');
    }
    final sourceLink = await comicDetailStore.loadPrimaryComicSourceLink(
      comicId,
    );

    return ReaderDebugSnapshot(
      generatedAt: DateTime.now(),
      comicId: comicId,
      loadMode: loadMode,
      controllerLifecycle: controllerLifecycle,
      localLibraryItemId: localItem?.id,
      sourcePlatformId: sourceLink?.sourcePlatformId,
      sourceComicId: sourceLink?.sourceComicId,
      linkStatus: sourceLink == null ? 'missing' : sourceLink.linkStatus,
      pageOrderId: pageOrder?.id,
      chapterId: chapterId,
    );
  }
}
