import 'package:flutter/foundation.dart';
import 'package:venera/features/comic_detail/data/comic_detail_models.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/foundation/reader/reader_open_target.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';

class ReaderResumeService {
  const ReaderResumeService({required this.readerSessions});

  final ReaderSessionRepository readerSessions;

  Future<ReaderOpenTarget?> loadPreferredResumeTarget(
    String comicId,
    ComicType type,
  ) async {
    final canonicalComicId = type == ComicType.local
        ? comicId
        : canonicalRemoteComicId(sourceKey: type.sourceKey, comicId: comicId);
    final canonicalActiveTab = await readerSessions.loadActiveReaderTab(
      canonicalComicId,
    );
    if (canonicalActiveTab != null) {
      final context = buildReaderRuntimeContext(
        comicId: comicId,
        type: type,
        chapterIndex: 0,
        page: canonicalActiveTab.currentPageIndex,
        chapterId: canonicalActiveTab.currentChapterId,
        sourceRef: canonicalActiveTab.sourceRef,
      );
      ReaderDiagnostics.recordCanonicalSessionEvent(
        event: 'reader.session.load.hit',
        loadMode: context.loadMode,
        sourceKey: context.sourceKey,
        comicId: context.canonicalComicId,
        chapterId: context.chapterId,
        chapterIndex: context.chapterIndex,
        page: context.page,
        sessionId: ReaderSessionRepository.sessionIdForComic(
          context.canonicalComicId,
        ),
        tabId: canonicalActiveTab.tabId,
        pageOrderId: canonicalActiveTab.pageOrderId,
      );
      ReaderDiagnostics.recordResumeLookupEvent(
        event: 'reader.session.load.canonical_hit',
        comicId: context.canonicalComicId,
        sourceKey: context.sourceKey,
        loadMode: context.loadMode,
        chapterId: context.chapterId,
        page: context.page,
        sessionId: ReaderSessionRepository.sessionIdForComic(
          context.canonicalComicId,
        ),
        tabId: canonicalActiveTab.tabId,
      );
      return ReaderOpenTarget(sourceRef: canonicalActiveTab.sourceRef);
    }
    return null;
  }
}

@visibleForTesting
ReaderOpenTarget? choosePreferredResumeTargetForTesting({
  required ReaderTabVm? canonicalActiveTab,
}) {
  final sourceRef = canonicalActiveTab?.sourceRef;
  return sourceRef == null ? null : ReaderOpenTarget(sourceRef: sourceRef);
}
