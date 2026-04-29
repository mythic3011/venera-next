import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/reader/reader_trace_recorder.dart';
import 'package:venera/foundation/source_ref.dart';

class ReaderDiagnostics {
  ReaderDiagnostics._();

  static int _nextCallId = 0;
  static final Map<String, DateTime> _callStarts = {};

  static Map<String, dynamic> toDiagnosticsJson() {
    return readerTraceRecorder.toDiagnosticsJson();
  }

  static String beginCall({
    required String functionName,
    required ReaderTracePhase phase,
    String? loadMode,
    String? sourceKey,
    String? comicId,
    String? chapterId,
    int? chapterIndex,
    int? page,
    String? imageKey,
  }) {
    final callId = '${DateTime.now().microsecondsSinceEpoch}-${_nextCallId++}';
    _callStarts[callId] = DateTime.now();
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'call.start',
        timestamp: DateTime.now(),
        phase: phase,
        functionName: functionName,
        callId: callId,
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        imageKey: imageKey,
      ),
    );
    return callId;
  }

  static void endCall({
    required String callId,
    required String functionName,
    required ReaderTracePhase phase,
    String? loadMode,
    String? sourceKey,
    String? comicId,
    String? chapterId,
    int? chapterIndex,
    int? page,
    String? resultSummary,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'call.end',
        timestamp: DateTime.now(),
        phase: phase,
        functionName: functionName,
        callId: callId,
        durationMs: _durationMs(callId),
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        resultSummary: resultSummary,
      ),
    );
  }

  static void failCall({
    required String callId,
    required String functionName,
    required ReaderTracePhase phase,
    required String errorMessage,
    String? errorCode,
    String? loadMode,
    String? sourceKey,
    String? comicId,
    String? chapterId,
    int? chapterIndex,
    int? page,
    String? imageKey,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'call.error',
        timestamp: DateTime.now(),
        phase: phase,
        functionName: functionName,
        callId: callId,
        durationMs: _durationMs(callId),
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        imageKey: imageKey,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
  }

  static void updateReaderState({
    required String lifecycle,
    required ComicType type,
    required String comicId,
    required int chapterIndex,
    required int page,
    required String mode,
    required bool isLoading,
    required int? imageCount,
    required int? maxPage,
    required int? imagesPerPage,
    String? chapterId,
    SourceRef? sourceRef,
  }) {
    readerTraceRecorder.updateReaderState(
      lifecycle: lifecycle,
      loadMode: type == ComicType.local ? 'local' : 'remote',
      sourceKey: type.sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      page: page,
      mode: mode,
      isLoading: isLoading,
      imageCount: imageCount,
      maxPage: maxPage,
      imagesPerPage: imagesPerPage,
      sourceRef: sourceRef == null
          ? null
          : ReaderSourceRefSnapshot(
              id: sourceRef.id,
              type: sourceRef.type.key,
              sourceKey: sourceRef.sourceKey,
              refId: sourceRef.refId,
              routeKey: sourceRef.routeKey,
              params: sourceRef.params,
            ),
    );
  }

  static void recordReaderLifecycle({
    required String event,
    required ComicType type,
    required String comicId,
    required int chapterIndex,
    required int page,
    String? chapterId,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: event,
        timestamp: DateTime.now(),
        loadMode: type == ComicType.local ? 'local' : 'remote',
        sourceKey: type.sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        phase: ReaderTracePhase.sourceResolution,
      ),
    );
  }

  static String beginPageListLoad({
    required String loadMode,
    required String sourceKey,
    required String comicId,
    required int chapterIndex,
    required int page,
    String? chapterId,
  }) {
    return beginCall(
      functionName: 'ReaderImages.loadPageList',
      phase: ReaderTracePhase.pageList,
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      page: page,
    );
  }

  static void endPageListLoad({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required String comicId,
    required int chapterIndex,
    required int page,
    required int pageCount,
  }) {
    endCall(
      callId: callId,
      functionName: 'ReaderImages.loadPageList',
      phase: ReaderTracePhase.pageList,
      loadMode: loadMode,
      sourceKey: sourceRef.sourceKey,
      comicId: comicId,
      chapterId: sourceRef.params['chapterId']?.toString(),
      chapterIndex: chapterIndex,
      page: page,
      resultSummary: pageCount == 0 ? 'emptyPageList' : 'pageCount=$pageCount',
    );
    recordPageListResult(
      event: pageCount == 0 ? 'emptyPageList' : 'pageList.load.success',
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: comicId,
      chapterIndex: chapterIndex,
      page: page,
    );
  }

  static void failPageListLoad({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required String comicId,
    required int chapterIndex,
    required int page,
    required String errorMessage,
    String? errorCode,
  }) {
    failCall(
      callId: callId,
      functionName: 'ReaderImages.loadPageList',
      phase: ReaderTracePhase.pageList,
      errorMessage: errorMessage,
      errorCode: errorCode,
      loadMode: loadMode,
      sourceKey: sourceRef.sourceKey,
      comicId: comicId,
      chapterId: sourceRef.params['chapterId']?.toString(),
      chapterIndex: chapterIndex,
      page: page,
    );
    recordPageListResult(
      event: errorCode == 'SOURCE_NOT_AVAILABLE'
          ? 'source.unavailable'
          : 'pageList.load.error',
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: comicId,
      chapterIndex: chapterIndex,
      page: page,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  static void recordPageListResult({
    required String event,
    required String loadMode,
    required SourceRef sourceRef,
    required String comicId,
    required int chapterIndex,
    required int page,
    String? errorCode,
    String? errorMessage,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: event,
        timestamp: DateTime.now(),
        loadMode: loadMode,
        sourceKey: sourceRef.sourceKey,
        comicId: comicId,
        chapterId: sourceRef.params['chapterId']?.toString(),
        chapterIndex: chapterIndex,
        page: page,
        errorCode: errorCode,
        errorMessage: errorMessage,
        phase: errorCode == 'SOURCE_NOT_AVAILABLE'
            ? ReaderTracePhase.sourceResolution
            : ReaderTracePhase.pageList,
      ),
    );
  }

  static void recordImageProviderCreated({
    required ComicType type,
    required String comicId,
    required String chapterId,
    required int chapterIndex,
    required int page,
    required String imageKey,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.provider.created',
        timestamp: DateTime.now(),
        loadMode: type == ComicType.local ? 'local' : 'remote',
        sourceKey: type.sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        imageKey: imageKey,
        phase: ReaderTracePhase.imageProvider,
      ),
    );
  }

  static void recordImageLoadError({required Object error, String? imageKey}) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.load.error',
        timestamp: DateTime.now(),
        imageKey: imageKey,
        errorMessage: error.toString(),
        phase: ReaderTracePhase.decode,
      ),
    );
  }

  static int? _durationMs(String callId) {
    final start = _callStarts.remove(callId);
    if (start == null) {
      return null;
    }
    return DateTime.now().difference(start).inMilliseconds;
  }
}
