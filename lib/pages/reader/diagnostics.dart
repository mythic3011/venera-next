part of 'reader.dart';

void _recordImageLoadErrorDiagnostics({
  required Object error,
  String? imageKey,
}) {
  ReaderDiagnostics.recordImageLoadError(error: error, imageKey: imageKey);
}

extension _ReaderDiagnosticsState on _ReaderState {
  void recordReaderOpenDiagnostics() {
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.open',
      type: type,
      comicId: cid,
      chapterId: widget.chapters?.ids.elementAtOrNull(chapter - 1),
      chapterIndex: chapter,
      page: page,
    );
    updateReaderDiagnostics('open');
  }

  void recordReaderDisposeDiagnostics() {
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: type,
      comicId: cid,
      chapterId: widget.chapters?.ids.elementAtOrNull(chapter - 1),
      chapterIndex: chapter,
      page: page,
    );
    updateReaderDiagnostics('dispose');
  }

  String beginPageListDiagnostics(String loadMode) {
    return ReaderDiagnostics.beginPageListLoad(
      loadMode: loadMode,
      sourceKey: type.sourceKey,
      comicId: cid,
      chapterId: widget.chapters?.ids.elementAtOrNull(chapter - 1),
      chapterIndex: chapter,
      page: page,
    );
  }

  void failPageListDiagnostics({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required String errorMessage,
    String? errorCode,
  }) {
    ReaderDiagnostics.failPageListLoad(
      callId: callId,
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: cid,
      chapterIndex: chapter,
      page: page,
      errorMessage: errorMessage,
      errorCode: errorCode,
    );
  }

  void endPageListDiagnostics({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required int pageCount,
  }) {
    ReaderDiagnostics.endPageListLoad(
      callId: callId,
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: cid,
      chapterIndex: chapter,
      page: page,
      pageCount: pageCount,
    );
    updateReaderDiagnostics('pageList.loaded');
  }

  void recordImageProviderDiagnostics({
    required String imageKey,
    required int imagePage,
  }) {
    ReaderDiagnostics.recordImageProviderCreated(
      type: type,
      comicId: cid,
      chapterId: eid,
      chapterIndex: chapter,
      page: imagePage,
      imageKey: imageKey,
    );
  }

  void updateReaderDiagnostics(String lifecycle) {
    ReaderDiagnostics.updateReaderState(
      lifecycle: lifecycle,
      type: type,
      comicId: cid,
      chapterId: widget.chapters?.ids.elementAtOrNull(chapter - 1),
      chapterIndex: chapter,
      page: page,
      mode: mode.key,
      isLoading: isLoading,
      imageCount: images?.length,
      maxPage: images == null ? null : maxPage,
      imagesPerPage: imagesPerPage,
      sourceRef: widget.sourceRef,
    );
  }
}
