import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:venera/features/comic_detail/data/comic_detail_models.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/foundation/source_ref.dart';

typedef LegacyResumeSourceRefLoader =
    FutureOr<SourceRef?> Function(String comicId, ComicType type);

class ReaderResumeService {
  const ReaderResumeService({
    required this.readerSessions,
    this.loadLegacyResumeSourceRef,
  });

  final ReaderSessionRepository readerSessions;
  final LegacyResumeSourceRefLoader? loadLegacyResumeSourceRef;

  Future<SourceRef?> loadPreferredResumeSourceRef(
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
      return canonicalActiveTab.sourceRef;
    }
    final legacyLoader = loadLegacyResumeSourceRef;
    if (legacyLoader == null) {
      ReaderDiagnostics.recordResumeLookupEvent(
        event: 'reader.session.load.legacy_fallback_miss',
        comicId: canonicalComicId,
        sourceKey: type.sourceKey,
        loadMode: type == ComicType.local ? 'local' : 'remote',
        fallbackSource: 'none',
      );
      return null;
    }
    final legacySourceRef = await legacyLoader(comicId, type);
    if (legacySourceRef != null) {
      ReaderDiagnostics.recordResumeLookupEvent(
        event: 'reader.session.load.legacy_fallback_hit',
        comicId: canonicalComicId,
        sourceKey: legacySourceRef.sourceKey,
        loadMode: legacySourceRef.type == SourceRefType.local
            ? 'local'
            : 'remote',
        chapterId: legacySourceRef.params['chapterId']?.toString(),
        fallbackSource: 'reading_resume_targets_v1',
      );
      return legacySourceRef;
    }
    ReaderDiagnostics.recordResumeLookupEvent(
      event: 'reader.session.load.legacy_fallback_miss',
      comicId: canonicalComicId,
      sourceKey: type.sourceKey,
      loadMode: type == ComicType.local ? 'local' : 'remote',
      fallbackSource: 'reading_resume_targets_v1',
    );
    return null;
  }
}

@visibleForTesting
SourceRef? choosePreferredResumeSourceRefForTesting({
  required ReaderTabVm? canonicalActiveTab,
}) {
  return canonicalActiveTab?.sourceRef;
}
