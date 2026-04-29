part of 'reader.dart';

void _recordImageLoadErrorDiagnostics({
  required Object error,
  String? imageKey,
  String? sourceKey,
  String? comicId,
  String? chapterId,
  int? page,
}) {
  ReaderDiagnostics.recordImageLoadError(
    error: error,
    imageKey: imageKey,
    sourceKey: sourceKey,
    comicId: comicId,
    chapterId: chapterId,
    page: page,
  );
}

@visibleForTesting
class ReaderPaginationDiagnostics {
  const ReaderPaginationDiagnostics({
    required this.imageCount,
    required this.maxPage,
    required this.imagesPerPage,
  });

  final int? imageCount;
  final int? maxPage;
  final int? imagesPerPage;
}

ReaderPaginationDiagnostics _buildReaderPaginationDiagnostics({
  required bool includePagination,
  required int? imageCount,
  required int? Function() maxPage,
  required int? Function() imagesPerPage,
}) {
  if (!includePagination || imageCount == null) {
    return ReaderPaginationDiagnostics(
      imageCount: imageCount,
      maxPage: null,
      imagesPerPage: null,
    );
  }
  return ReaderPaginationDiagnostics(
    imageCount: imageCount,
    maxPage: maxPage(),
    imagesPerPage: imagesPerPage(),
  );
}

@visibleForTesting
ReaderPaginationDiagnostics buildReaderPaginationDiagnosticsForTesting({
  required bool includePagination,
  required int? imageCount,
  required int? Function() maxPage,
  required int? Function() imagesPerPage,
}) {
  return _buildReaderPaginationDiagnostics(
    includePagination: includePagination,
    imageCount: imageCount,
    maxPage: maxPage,
    imagesPerPage: imagesPerPage,
  );
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
    final chapterId = widget.chapters?.ids.elementAtOrNull(chapter - 1);
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: type,
      comicId: cid,
      chapterId: chapterId,
      chapterIndex: chapter,
      page: page,
    );
    updateReaderDiagnostics('dispose', includePagination: false);
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

  void updateReaderDiagnostics(
    String lifecycle, {
    bool includePagination = true,
  }) {
    final pagination = _buildReaderPaginationDiagnostics(
      includePagination: includePagination,
      imageCount: images?.length,
      maxPage: () => maxPage,
      imagesPerPage: () => imagesPerPage,
    );
    ReaderDiagnostics.updateReaderState(
      lifecycle: lifecycle,
      type: type,
      comicId: cid,
      chapterId: widget.chapters?.ids.elementAtOrNull(chapter - 1),
      chapterIndex: chapter,
      page: page,
      mode: mode.key,
      isLoading: isLoading,
      imageCount: pagination.imageCount,
      maxPage: pagination.maxPage,
      imagesPerPage: pagination.imagesPerPage,
      sourceRef: widget.sourceRef,
    );
  }
}
