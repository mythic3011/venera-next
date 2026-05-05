import 'package:flutter/foundation.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';

typedef ReaderSessionEventRecorder =
    void Function(
      String event, {
      required ReaderRuntimeContext context,
      String? sessionId,
      String? tabId,
      String? pageOrderId,
      String? reason,
    });

void recordReaderSessionDiagnosticEvent(
  String event, {
  required ReaderRuntimeContext context,
  String? sessionId,
  String? tabId,
  String? pageOrderId,
  String? reason,
}) {
  ReaderDiagnostics.recordCanonicalSessionEvent(
    event: event,
    loadMode: context.loadMode,
    sourceKey: context.sourceKey,
    comicId: context.canonicalComicId,
    chapterId: context.chapterId,
    chapterIndex: context.chapterIndex,
    page: context.page,
    sessionId: sessionId,
    tabId: tabId,
    pageOrderId: pageOrderId,
    reason: reason,
  );
}

class ReaderSessionPersistenceService {
  const ReaderSessionPersistenceService({
    required this.repository,
    this.recordEvent,
  });

  final ReaderSessionRepository repository;
  final ReaderSessionEventRecorder? recordEvent;

  Future<void> persistCurrentLocation(
    ReaderRuntimeContext context, {
    String? pageOrderId,
  }) async {
    final sessionId = ReaderSessionRepository.sessionIdForComic(
      context.canonicalComicId,
    );
    final tabId = ReaderSessionRepository.defaultTabIdForSourceRef(
      context.sourceRef,
    );
    recordEvent?.call(
      'reader.session.upsert.start',
      context: context,
      sessionId: sessionId,
      tabId: tabId,
      pageOrderId: pageOrderId,
    );
    final result = await repository.upsertCurrentLocation(
      comicId: context.canonicalComicId,
      chapterId: context.chapterId,
      pageIndex: context.page,
      sourceRef: context.sourceRef,
      pageOrderId: pageOrderId,
    );
    if (!result.written) {
      recordEvent?.call(
        'reader.session.upsert.skip',
        context: context,
        sessionId: sessionId,
        tabId: tabId,
        pageOrderId: pageOrderId,
        reason: _persistSkipReasonName(result.skipReason),
      );
      return;
    }
    recordEvent?.call(
      'reader.session.upsert.success',
      context: context,
      sessionId: sessionId,
      tabId: tabId,
      pageOrderId: pageOrderId,
    );
  }
}

String _persistSkipReasonName(ReaderSessionPersistSkipReason? reason) {
  return switch (reason) {
    ReaderSessionPersistSkipReason.unchanged => 'unchanged',
    ReaderSessionPersistSkipReason.unchangedMemory => 'unchanged_memory',
    ReaderSessionPersistSkipReason.duplicateInFlight => 'duplicate_in_flight',
    null => 'unknown',
  };
}

@visibleForTesting
Future<void> persistReaderSessionContextForTesting({
  required ReaderSessionRepository repository,
  required ReaderRuntimeContext context,
  String? pageOrderId,
  ReaderSessionEventRecorder? recordEvent,
}) {
  return ReaderSessionPersistenceService(
    repository: repository,
    recordEvent: recordEvent,
  ).persistCurrentLocation(context, pageOrderId: pageOrderId);
}
