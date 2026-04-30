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
    final context = currentReaderContext();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.open',
      type: type,
      comicId: cid,
      chapterId: context.chapterId,
      chapterIndex: context.chapterIndex,
      page: context.page,
      sourceKey: context.sourceKey,
      loadMode: context.loadMode,
    );
    updateReaderDiagnostics('open');
  }

  void recordReaderDisposeDiagnostics() {
    final context = currentReaderContext();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: type,
      comicId: cid,
      chapterId: context.chapterId,
      chapterIndex: context.chapterIndex,
      page: context.page,
      sourceKey: context.sourceKey,
      loadMode: context.loadMode,
    );
    updateReaderDiagnostics('dispose', includePagination: false);
  }

  String beginPageListDiagnostics(String loadMode) {
    final context = currentReaderContext();
    return ReaderDiagnostics.beginPageListLoad(
      loadMode: loadMode,
      sourceKey: context.sourceKey,
      comicId: cid,
      chapterId: context.chapterId,
      chapterIndex: context.chapterIndex,
      page: context.page,
    );
  }

  void failPageListDiagnostics({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required String errorMessage,
    String? errorCode,
  }) {
    final context = currentReaderContext();
    ReaderDiagnostics.failPageListLoad(
      callId: callId,
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: cid,
      chapterIndex: context.chapterIndex,
      page: context.page,
      errorMessage: errorMessage,
      sourceKey: context.sourceKey,
      chapterId: context.chapterId,
      errorCode: errorCode,
    );
  }

  void endPageListDiagnostics({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required int pageCount,
  }) {
    final context = currentReaderContext();
    ReaderDiagnostics.endPageListLoad(
      callId: callId,
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: cid,
      chapterIndex: context.chapterIndex,
      page: context.page,
      pageCount: pageCount,
      sourceKey: context.sourceKey,
      chapterId: context.chapterId,
    );
    updateReaderDiagnostics('pageList.loaded');
  }

  void recordImageProviderDiagnostics({
    required String imageKey,
    required int imagePage,
  }) {
    final context = currentReaderContext(pageOverride: imagePage);
    ReaderDiagnostics.recordImageProviderCreated(
      type: type,
      comicId: cid,
      chapterId: context.chapterId,
      chapterIndex: context.chapterIndex,
      page: context.page,
      imageKey: imageKey,
    );
  }

  void updateReaderDiagnostics(
    String lifecycle, {
    bool includePagination = true,
  }) {
    final context = currentReaderContext();
    final pagination = includePagination
        ? _buildReaderPaginationDiagnostics(
            includePagination: true,
            imageCount: images?.length,
            maxPage: () => maxPage,
            imagesPerPage: () => imagesPerPage,
          )
        : (_lastLoadedPaginationDiagnostics ??
              _buildReaderPaginationDiagnostics(
                includePagination: false,
                imageCount: images?.length,
                maxPage: () => maxPage,
                imagesPerPage: () => imagesPerPage,
              ));
    ReaderDiagnostics.updateReaderState(
      lifecycle: lifecycle,
      type: type,
      comicId: cid,
      chapterId: context.chapterId,
      chapterIndex: context.chapterIndex,
      page: context.page,
      mode: mode.key,
      isLoading: isLoading,
      imageCount: pagination.imageCount,
      maxPage: pagination.maxPage,
      imagesPerPage: pagination.imagesPerPage,
      sourceKey: context.sourceKey,
      loadMode: context.loadMode,
      sourceRef: context.sourceRef,
    );
  }
}
