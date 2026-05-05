part of 'reader.dart';

const Set<String> _readerExpectedRouteTeardownEvents = <String>{
  'didPop',
  'didRemove',
  'didReplace',
};

@visibleForTesting
String? normalizeReaderRouteLifecycleEventForTesting(String? event) {
  if (event == null || event.isEmpty) {
    return null;
  }
  return event;
}

@visibleForTesting
bool shouldWarnOnShortLivedReaderDisposeForTesting(
  String? routeLifecycleEvent,
) {
  final normalized = normalizeReaderRouteLifecycleEventForTesting(
    routeLifecycleEvent,
  );
  return !_readerExpectedRouteTeardownEvents.contains(normalized);
}

@visibleForTesting
void emitReaderShortLivedDisposeDiagnosticForTesting(
  Map<String, Object?> data,
) {
  if (!shouldWarnOnShortLivedReaderDisposeForTesting(
    data['routeLifecycleEvent']?.toString(),
  )) {
    return;
  }
  AppDiagnostics.warn(
    'reader.lifecycle',
    'reader.dispose.short_lived',
    data: data,
  );
}

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

@visibleForTesting
Map<String, Object?> buildReaderTabRetentionDiagnosticForTesting({
  required String expectedReaderTabId,
  required String? activeReaderTabId,
  required String? pageOrderId,
  required String comicId,
  required String loadMode,
  required String sourceKey,
  required String chapterId,
  required int chapterIndex,
  required int page,
}) {
  final retained = activeReaderTabId == expectedReaderTabId;
  return {
    'comicId': comicId,
    'loadMode': loadMode,
    'sourceKey': sourceKey,
    'chapterId': chapterId,
    'chapterIndex': chapterIndex,
    'page': page,
    'expectedReaderTabId': expectedReaderTabId,
    'activeReaderTabId': activeReaderTabId,
    'pageOrderId': pageOrderId,
    'retained': retained,
    'status': retained
        ? 'active'
        : (activeReaderTabId == null ? 'missingActiveTab' : 'mismatch'),
  };
}

@visibleForTesting
String readerTabRetentionEventNameForTesting(Map<String, Object?> data) {
  return data['status'] == 'missingActiveTab'
      ? 'reader.tab.retention.missing'
      : 'reader.tab.retention.afterPageList';
}

@visibleForTesting
void emitReaderTabRetentionDiagnosticForTesting(Map<String, Object?> data) {
  final event = readerTabRetentionEventNameForTesting(data);
  if (data['status'] == 'missingActiveTab') {
    AppDiagnostics.warn('reader.lifecycle', event, data: data);
    return;
  }
  if (data['retained'] == true) {
    AppDiagnostics.trace('reader.lifecycle', event, data: data);
    return;
  }
  AppDiagnostics.warn('reader.lifecycle', event, data: data);
}

@visibleForTesting
Map<String, Object?> buildReaderRouteDiagnosticSnapshotForTesting({
  int? routeHash,
  String? routeName,
  String? routeSettingsName,
  String? routeSettingsArgumentsType,
  String? routeRuntimeType,
  String? routeDiagnosticIdentity,
  int? navigatorHash,
  int? rootNavigatorHash,
  int? nearestNavigatorHash,
  int? mainNavigatorHash,
  bool? rootNavigator,
  bool? nestedNavigator,
  Object? observerAttached,
  String? navigatorRole,
  String? observerStatus,
  int? previousRouteHash,
  String? previousRouteDiagnosticIdentity,
  String? navigatorLifecycleEvent,
}) {
  return {
    if (routeHash != null) 'routeHash': routeHash,
    if (routeName != null) 'routeName': routeName,
    if (routeSettingsName != null) 'routeSettingsName': routeSettingsName,
    if (routeSettingsArgumentsType != null)
      'routeSettingsArgumentsType': routeSettingsArgumentsType,
    if (routeRuntimeType != null) 'routeRuntimeType': routeRuntimeType,
    if (routeDiagnosticIdentity != null)
      'routeDiagnosticIdentity': routeDiagnosticIdentity,
    if (navigatorHash != null) 'navigatorHash': navigatorHash,
    if (rootNavigatorHash != null) 'rootNavigatorHash': rootNavigatorHash,
    if (nearestNavigatorHash != null)
      'nearestNavigatorHash': nearestNavigatorHash,
    if (mainNavigatorHash != null) 'mainNavigatorHash': mainNavigatorHash,
    if (rootNavigator != null) 'rootNavigator': rootNavigator,
    if (nestedNavigator != null) 'nestedNavigator': nestedNavigator,
    if (observerAttached != null) 'observerAttached': observerAttached,
    if (navigatorRole != null) 'navigatorRole': navigatorRole,
    if (observerStatus != null) 'observerStatus': observerStatus,
    if (previousRouteHash != null) 'previousRouteHash': previousRouteHash,
    if (previousRouteDiagnosticIdentity != null)
      'previousRouteDiagnosticIdentity': previousRouteDiagnosticIdentity,
    if (navigatorLifecycleEvent != null)
      'navigatorLifecycleEvent': navigatorLifecycleEvent,
  };
}

@visibleForTesting
Map<String, Object?> buildReaderParentShellDiagnosticForTesting({
  required String owner,
  required String branch,
  required bool readerChildMounted,
  required String comicId,
  required String loadMode,
  required String sourceKey,
  required String expectedReaderTabId,
  required String? activeReaderTabId,
  required String? pageOrderId,
  String? chapterId,
  int? chapterIndex,
  int? page,
  int? selectedIndex,
  int? currentPage,
  String? routeName,
  Map<String, Object?> routeSnapshot = const {},
  String? requestEntrypoint,
  String? requestCaller,
  String? requestSourceRefId,
  int? parentStateHash,
  String? parentKey,
  String? readerChildKey,
  String? reason,
  int? openDurationMs,
}) {
  final retainedTab = activeReaderTabId == expectedReaderTabId;
  return {
    'owner': owner,
    'branch': branch,
    'readerChildMounted': readerChildMounted,
    'comicId': comicId,
    'loadMode': loadMode,
    'sourceKey': sourceKey,
    'chapterId': chapterId,
    'chapterIndex': chapterIndex,
    'page': page,
    'selectedIndex': selectedIndex,
    'currentPage': currentPage,
    'routeName': routeName,
    ...routeSnapshot,
    'expectedReaderTabId': expectedReaderTabId,
    'activeReaderTabId': activeReaderTabId,
    'pageOrderId': pageOrderId,
    'retainedTab': retainedTab,
    if (requestEntrypoint != null) 'requestEntrypoint': requestEntrypoint,
    if (requestCaller != null) 'requestCaller': requestCaller,
    if (requestSourceRefId != null) 'requestSourceRefId': requestSourceRefId,
    if (parentStateHash != null) 'parentStateHash': parentStateHash,
    'parentKey': parentKey,
    'readerChildKey': readerChildKey,
    if (reason != null) 'disposeReason': reason,
    if (reason != null) 'reason': reason,
    if (openDurationMs != null) 'openDurationMs': openDurationMs,
  };
}

@visibleForTesting
void emitReaderParentShellBuildDiagnosticForTesting(Map<String, Object?> data) {
  ReaderDiagnostics.recordReaderLifecycle(
    event: 'reader.parent.shell.build',
    type: ComicType.fromKey(data['sourceKey']?.toString() ?? 'local'),
    comicId: data['comicId']?.toString() ?? '',
    chapterId: data['chapterId']?.toString(),
    chapterIndex: data['chapterIndex'] as int? ?? 0,
    page: data['page'] as int? ?? 0,
    data: data,
    resultSummary:
        'branch=${data['branch']} retainedTab=${data['retainedTab']} '
        'entrypoint=${data['requestEntrypoint']} '
        'routeHash=${data['routeHash']} '
        'activeReaderTabId=${data['activeReaderTabId']} '
        'expectedReaderTabId=${data['expectedReaderTabId']} '
        'pageOrderId=${data['pageOrderId']}',
  );
  AppDiagnostics.trace(
    'reader.lifecycle',
    'reader.parent.shell.build',
    data: data,
  );
}

@visibleForTesting
void emitReaderParentUnmountDiagnosticForTesting(Map<String, Object?> data) {
  if (!shouldWarnOnShortLivedReaderDisposeForTesting(
    data['routeLifecycleEvent']?.toString(),
  )) {
    return;
  }
  ReaderDiagnostics.recordReaderLifecycle(
    event: 'reader.parent.unmount.retainedTab',
    type: ComicType.fromKey(data['sourceKey']?.toString() ?? 'local'),
    comicId: data['comicId']?.toString() ?? '',
    chapterId: data['chapterId']?.toString(),
    chapterIndex: data['chapterIndex'] as int? ?? 0,
    page: data['page'] as int? ?? 0,
    data: data,
    resultSummary:
        'reason=${data['disposeReason'] ?? data['reason']} '
        'entrypoint=${data['requestEntrypoint']} '
        'routeHash=${data['routeHash']} '
        'retainedTab=${data['retainedTab']} '
        'activeReaderTabId=${data['activeReaderTabId']} '
        'expectedReaderTabId=${data['expectedReaderTabId']} '
        'pageOrderId=${data['pageOrderId']} '
        'openDurationMs=${data['openDurationMs']}',
  );
  AppDiagnostics.warn(
    'reader.lifecycle',
    'reader.parent.unmount.retainedTab',
    data: data,
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
    final expectedReaderTabId =
        ReaderSessionRepository.defaultTabIdForSourceRef(context.sourceRef);
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.open',
      type: type,
      comicId: cid,
      chapterId: context.chapterId,
      chapterIndex: context.chapterIndex,
      page: context.page,
      sourceKey: context.sourceKey,
      loadMode: context.loadMode,
      resultSummary: 'expectedReaderTabId=$expectedReaderTabId',
      data: {
        'expectedReaderTabId': expectedReaderTabId,
        'sourceRefId': context.sourceRef.id,
        'sourceRefType': context.sourceRef.type.key,
        'sourceRefRouteKey': context.sourceRef.routeKey,
      },
    );
    updateReaderDiagnostics('open');
  }

  void recordReaderDisposeDiagnostics({DateTime? openedAt}) {
    final context = currentReaderContext();
    final expectedReaderTabId =
        ReaderSessionRepository.defaultTabIdForSourceRef(context.sourceRef);
    final routeName = _routeNameSnapshot;
    final openDurationMs = openedAt == null
        ? null
        : DateTime.now().difference(openedAt).inMilliseconds;
    final disposeCause = 'State.dispose';
    final disposeOwner = 'Reader.dispose';
    final resultSummary = [
      'cause=$disposeCause',
      'owner=$disposeOwner',
      'expectedReaderTabId=$expectedReaderTabId',
      if (openDurationMs != null) 'openDurationMs=$openDurationMs',
    ].join(' ');
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: type,
      comicId: cid,
      chapterId: context.chapterId,
      chapterIndex: context.chapterIndex,
      page: context.page,
      sourceKey: context.sourceKey,
      loadMode: context.loadMode,
      resultSummary: resultSummary,
      data: {
        'disposeCause': disposeCause,
        'disposeOwner': disposeOwner,
        'routeName': routeName,
        'openDurationMs': openDurationMs,
        'expectedReaderTabId': expectedReaderTabId,
        'sourceRefId': context.sourceRef.id,
        'sourceRefType': context.sourceRef.type.key,
        'sourceRefRouteKey': context.sourceRef.routeKey,
        'widgetHashCode': widget.hashCode,
        'stateHashCode': hashCode,
      },
    );
    if (openDurationMs != null && openDurationMs < 5000) {
      final routeLifecycleEvent = navigatorLifecycleDiagnosticForRouteHash(
        _routeHashSnapshot,
      )?['event']?.toString();
      if (shouldWarnOnShortLivedReaderDisposeForTesting(routeLifecycleEvent)) {
        emitReaderShortLivedDisposeDiagnosticForTesting({
          'disposeCause': disposeCause,
          'disposeOwner': disposeOwner,
          'routeName': routeName,
          'routeLifecycleEvent': routeLifecycleEvent,
          'openDurationMs': openDurationMs,
          'loadMode': context.loadMode,
          'sourceKey': context.sourceKey,
          'comicId': context.comicId,
          'chapterId': context.chapterId,
          'chapterIndex': context.chapterIndex,
          'page': context.page,
          'mode': mode.key,
          'imageCount': images?.length,
          'expectedReaderTabId': expectedReaderTabId,
          'sourceRefId': context.sourceRef.id,
          'sourceRefType': context.sourceRef.type.key,
          'sourceRefRouteKey': context.sourceRef.routeKey,
          'widgetHashCode': widget.hashCode,
          'stateHashCode': hashCode,
        });
      }
    }
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

  void recordReaderTabRetentionAfterPageListSuccess() {
    final context = currentReaderContext();
    final expectedReaderTabId =
        ReaderSessionRepository.defaultTabIdForSourceRef(context.sourceRef);
    unawaited(() async {
      try {
        final activeTab = await App.repositories.readerSession
            .loadActiveReaderTab(context.canonicalComicId);
        final data = buildReaderTabRetentionDiagnosticForTesting(
          expectedReaderTabId: expectedReaderTabId,
          activeReaderTabId: activeTab?.tabId,
          pageOrderId: activeTab?.pageOrderId,
          comicId: context.canonicalComicId,
          loadMode: context.loadMode,
          sourceKey: context.sourceKey,
          chapterId: context.chapterId,
          chapterIndex: context.chapterIndex,
          page: context.page,
        );
        emitReaderTabRetentionDiagnosticForTesting(data);
      } catch (error) {
        AppDiagnostics.warn(
          'reader.lifecycle',
          'reader.tab.retention.afterPageList',
          data: {
            'comicId': context.canonicalComicId,
            'loadMode': context.loadMode,
            'sourceKey': context.sourceKey,
            'chapterId': context.chapterId,
            'chapterIndex': context.chapterIndex,
            'page': context.page,
            'expectedReaderTabId': expectedReaderTabId,
            'status': 'checkFailed',
            'error': error.toString(),
          },
        );
      }
    }());
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
