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
  String? unavailableReason,
}) {
  if (!includePagination || imageCount == null) {
    return ReaderPaginationDiagnostics(
      imageCount: imageCount,
      maxPage: null,
      imagesPerPage: null,
    );
  }
  try {
    return ReaderPaginationDiagnostics(
      imageCount: imageCount,
      maxPage: maxPage(),
      imagesPerPage: imagesPerPage(),
    );
  } catch (error) {
    final fallbackReason =
        unavailableReason ?? 'pagination_snapshot_unavailable';
    AppDiagnostics.warn(
      'reader.lifecycle',
      'pagination.diagnostics.unavailable',
      data: {'reason': fallbackReason, 'error': error.toString()},
    );
    return ReaderPaginationDiagnostics(
      imageCount: imageCount,
      maxPage: null,
      imagesPerPage: null,
    );
  }
}

@visibleForTesting
ReaderPaginationDiagnostics buildReaderPaginationDiagnosticsForTesting({
  required bool includePagination,
  required int? imageCount,
  required int? Function() maxPage,
  required int? Function() imagesPerPage,
  String? unavailableReason,
}) {
  return _buildReaderPaginationDiagnostics(
    includePagination: includePagination,
    imageCount: imageCount,
    maxPage: maxPage,
    imagesPerPage: imagesPerPage,
    unavailableReason: unavailableReason,
  );
}

extension _ReaderDiagnosticsState on _ReaderState {
  Map<String, Object?> _readerBuildDiagnosticData({
    required BuildContext buildContext,
    required String owner,
    required String imagesKey,
    required String chapterIdSnapshot,
    required String readerIdentitySnapshot,
    required int pageSnapshot,
    required int imagesPerPageSnapshot,
    required int? imageCountSnapshot,
    Map<String, Object?> extra = const {},
  }) {
    final context = currentReaderContext();
    final routeName = ModalRoute.of(buildContext)?.settings.name;
    return {
      'owner': owner,
      'loadMode': context.loadMode,
      'sourceKey': context.sourceKey,
      'comicId': context.comicId,
      'chapterId': context.chapterId,
      'chapterIndex': context.chapterIndex,
      'page': pageSnapshot,
      'mode': mode.key,
      'imageCount': imageCountSnapshot,
      'imagesPerPage': imagesPerPageSnapshot,
      'routeName': routeName,
      'imagesKey': imagesKey,
      'chapterIdSnapshot': chapterIdSnapshot,
      'readerIdentitySnapshot': readerIdentitySnapshot,
      'widgetHashCode': widget.hashCode,
      'stateHashCode': hashCode,
      ...extra,
    };
  }

  void recordReaderWidgetBuiltDiagnostics({
    required BuildContext buildContext,
    required String owner,
    required String imagesKey,
    required String chapterIdSnapshot,
    required String readerIdentitySnapshot,
    required int pageSnapshot,
    required int imagesPerPageSnapshot,
    required int? imageCountSnapshot,
  }) {
    AppDiagnostics.trace(
      'reader.lifecycle',
      'reader.widget.built',
      data: _readerBuildDiagnosticData(
        buildContext: buildContext,
        owner: owner,
        imagesKey: imagesKey,
        chapterIdSnapshot: chapterIdSnapshot,
        readerIdentitySnapshot: readerIdentitySnapshot,
        pageSnapshot: pageSnapshot,
        imagesPerPageSnapshot: imagesPerPageSnapshot,
        imageCountSnapshot: imageCountSnapshot,
      ),
    );
  }

  void recordReaderOverlayEntryBuiltDiagnostics({
    required BuildContext buildContext,
    required String owner,
    required String imagesKey,
    required String chapterIdSnapshot,
    required String readerIdentitySnapshot,
    required int pageSnapshot,
    required int imagesPerPageSnapshot,
    required int? imageCountSnapshot,
  }) {
    AppDiagnostics.trace(
      'reader.lifecycle',
      'reader.overlay.entry.built',
      data: _readerBuildDiagnosticData(
        buildContext: buildContext,
        owner: owner,
        imagesKey: imagesKey,
        chapterIdSnapshot: chapterIdSnapshot,
        readerIdentitySnapshot: readerIdentitySnapshot,
        pageSnapshot: pageSnapshot,
        imagesPerPageSnapshot: imagesPerPageSnapshot,
        imageCountSnapshot: imageCountSnapshot,
      ),
    );
  }

  void recordReaderPaginationChangedDuringBuildDiagnostics({
    required BuildContext buildContext,
    required String owner,
    required int beforePage,
    required int afterPage,
    required int beforeImagesPerPage,
    required int afterImagesPerPage,
    required String imagesKey,
    required String chapterIdSnapshot,
    required String readerIdentitySnapshot,
    required int? imageCountSnapshot,
  }) {
    AppDiagnostics.warn(
      'reader.lifecycle',
      'reader.pagination.changed.during.build',
      data: _readerBuildDiagnosticData(
        buildContext: buildContext,
        owner: owner,
        imagesKey: imagesKey,
        chapterIdSnapshot: chapterIdSnapshot,
        readerIdentitySnapshot: readerIdentitySnapshot,
        pageSnapshot: afterPage,
        imagesPerPageSnapshot: afterImagesPerPage,
        imageCountSnapshot: imageCountSnapshot,
        extra: {
          'beforePage': beforePage,
          'afterPage': afterPage,
          'beforeImagesPerPage': beforeImagesPerPage,
          'afterImagesPerPage': afterImagesPerPage,
        },
      ),
    );
  }

  void recordImageControllerLifecycle(
    String lifecycle, {
    required String owner,
    bool includePagination = true,
    bool? ready,
    Map<String, Object?> data = const {},
  }) {
    final context = currentReaderContext();
    final pagination = _buildReaderPaginationDiagnostics(
      includePagination: includePagination && images != null,
      imageCount: images?.length,
      maxPage: () => maxPage,
      imagesPerPage: () => mode.isContinuous ? 1 : imagesPerPage,
      unavailableReason: lifecycle == 'dispose'
          ? 'context_unavailable_during_dispose'
          : null,
    );
    ReaderDiagnostics.updateReaderState(
      lifecycle: 'imageController.$lifecycle',
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
    AppDiagnostics.trace(
      'reader.lifecycle',
      'imageController.$lifecycle',
      data: {
        'owner': owner,
        'ready': ready ?? hasImageViewController,
        'comicId': context.comicId,
        'chapterId': context.chapterId,
        'chapterIndex': context.chapterIndex,
        'page': context.page,
        ...data,
      },
    );
  }

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
