part of 'reader.dart';

ComicChapters? buildCanonicalReaderChapters(List<ChapterVm> chapters) {
  if (chapters.isEmpty) {
    return null;
  }
  return ComicChapters({
    for (final chapter in chapters) chapter.chapterId: chapter.title,
  });
}

List<String> buildCanonicalReaderTags(ComicDetailViewModel detail) {
  return [
    ...detail.userTags.map((tag) => tag.name),
    ...detail.sourceTags.map(
      (tag) =>
          tag.namespace.isEmpty ? tag.name : '${tag.namespace}:${tag.name}',
    ),
  ];
}

class _CanonicalReaderHistoryModel with HistoryMixin {
  _CanonicalReaderHistoryModel({
    required this.title,
    required this.cover,
    required this.id,
    required this.historyType,
    this.subTitle,
  });

  @override
  final String title;

  @override
  final String? subTitle;

  @override
  final String cover;

  @override
  final String id;

  @override
  final ComicType historyType;
}

class ReaderInitialPosition {
  final int chapter;
  final int page;
  final int? group;

  const ReaderInitialPosition({
    required this.chapter,
    required this.page,
    required this.group,
  });
}

enum ReaderOpenRequestIdentityErrorCode {
  missingSourceAuthority,
  sourceKeyMismatch,
  localComicIdMismatch,
}

class ReaderOpenRequestIdentityError implements Exception {
  const ReaderOpenRequestIdentityError(this.code, {required this.message});

  final ReaderOpenRequestIdentityErrorCode code;
  final String message;

  String get codeKey => switch (code) {
    ReaderOpenRequestIdentityErrorCode.missingSourceAuthority =>
      'missingSourceAuthority',
    ReaderOpenRequestIdentityErrorCode.sourceKeyMismatch => 'sourceKeyMismatch',
    ReaderOpenRequestIdentityErrorCode.localComicIdMismatch =>
      'localComicIdMismatch',
  };

  @override
  String toString() => 'ReaderOpenRequestIdentityError($codeKey): $message';
}

class ReaderOpenRequest {
  final String comicId;
  final SourceRef? sourceRef;
  final String? sourceKey;
  final int? initialEp;
  final int? initialPage;
  final int? initialGroup;
  final String? diagnosticEntrypoint;
  final String? diagnosticCaller;

  factory ReaderOpenRequest({
    required String comicId,
    SourceRef? sourceRef,
    String? sourceKey,
    int? initialEp,
    int? initialPage,
    int? initialGroup,
    String? diagnosticEntrypoint,
    String? diagnosticCaller,
  }) {
    final normalizedSourceKey = _resolveReaderOpenRequestSourceKey(
      sourceRef: sourceRef,
      sourceKey: sourceKey,
    );
    _assertReaderOpenRequestAuthority(
      comicId: comicId,
      sourceRef: sourceRef,
      sourceKey: sourceKey,
      normalizedSourceKey: normalizedSourceKey,
    );
    return ReaderOpenRequest._(
      comicId: comicId,
      sourceRef: sourceRef,
      sourceKey: normalizedSourceKey,
      initialEp: initialEp,
      initialPage: initialPage,
      initialGroup: initialGroup,
      diagnosticEntrypoint: diagnosticEntrypoint,
      diagnosticCaller: diagnosticCaller,
    );
  }

  const ReaderOpenRequest._({
    required this.comicId,
    required this.sourceRef,
    required this.sourceKey,
    required this.initialEp,
    required this.initialPage,
    required this.initialGroup,
    required this.diagnosticEntrypoint,
    required this.diagnosticCaller,
  });

  String? get sourceRefId => sourceRef?.id;
}

String? _resolveReaderOpenRequestSourceKey({
  required SourceRef? sourceRef,
  required String? sourceKey,
}) {
  final explicitKey = sourceKey?.trim();
  if (sourceRef != null) {
    return sourceRef.sourceKey;
  }
  if (explicitKey == null || explicitKey.isEmpty) {
    return null;
  }
  return explicitKey;
}

void _assertReaderOpenRequestAuthority({
  required String comicId,
  required SourceRef? sourceRef,
  required String? sourceKey,
  required String? normalizedSourceKey,
}) {
  if (sourceRef == null && normalizedSourceKey == null) {
    throw const ReaderOpenRequestIdentityError(
      ReaderOpenRequestIdentityErrorCode.missingSourceAuthority,
      message: 'Reader open request requires sourceRef or sourceKey.',
    );
  }
  final explicitKey = sourceKey?.trim();
  if (sourceRef != null &&
      explicitKey != null &&
      explicitKey.isNotEmpty &&
      explicitKey != sourceRef.sourceKey) {
    throw ReaderOpenRequestIdentityError(
      ReaderOpenRequestIdentityErrorCode.sourceKeyMismatch,
      message:
          'Reader open request sourceKey "$explicitKey" does not match '
          'sourceRef.sourceKey "${sourceRef.sourceKey}".',
    );
  }
  if (sourceRef?.type == SourceRefType.local) {
    final localComicId = sourceRef?.params['localComicId']?.toString();
    if (localComicId != null &&
        localComicId.isNotEmpty &&
        localComicId != comicId) {
      throw ReaderOpenRequestIdentityError(
        ReaderOpenRequestIdentityErrorCode.localComicIdMismatch,
        message:
            'Reader open request comicId "$comicId" does not match '
            'local SourceRef comicId "$localComicId".',
      );
    }
  }
}

SourceRef? resolveReaderOpenSourceRef({
  required String comicId,
  SourceRef? explicitSourceRef,
  SourceRef? resumeSourceRef,
  String? sourceKey,
}) {
  if (explicitSourceRef != null) {
    return explicitSourceRef;
  }
  if (resumeSourceRef != null) {
    return resumeSourceRef;
  }
  final key = sourceKey;
  if (key == null || key.isEmpty) {
    return null;
  }
  return SourceRef.fromLegacy(comicId: comicId, sourceKey: key);
}

@visibleForTesting
ReaderOpenRequest normalizeLegacyReaderOpenRequest({
  required String comicId,
  SourceRef? explicitSourceRef,
  String? sourceKey,
  int? initialEp,
  int? initialPage,
  int? initialGroup,
  String? diagnosticEntrypoint,
  String? diagnosticCaller,
}) {
  return ReaderOpenRequest(
    comicId: comicId,
    sourceRef: resolveReaderOpenSourceRef(
      comicId: comicId,
      explicitSourceRef: explicitSourceRef,
      resumeSourceRef: null,
      sourceKey: sourceKey,
    ),
    sourceKey: explicitSourceRef?.sourceKey ?? sourceKey,
    initialEp: initialEp,
    initialPage: initialPage,
    initialGroup: initialGroup,
    diagnosticEntrypoint: diagnosticEntrypoint,
    diagnosticCaller: diagnosticCaller,
  );
}

ReaderInitialPosition resolveReaderInitialPosition({
  required int? requestedEp,
  required int? requestedPage,
  required int? requestedGroup,
  required int historyEp,
  required int historyPage,
  required int? historyGroup,
}) {
  return ReaderInitialPosition(
    chapter: requestedEp ?? historyEp,
    page: requestedPage ?? historyPage,
    group: requestedGroup ?? historyGroup,
  );
}

History buildReaderCompatibilityHistory({
  required HistoryMixin model,
  required ComicChapters? chapters,
  required ReaderTabVm? canonicalActiveTab,
}) {
  final chapterId = canonicalActiveTab?.currentChapterId;
  final chapterIds = chapters?.ids.toList(growable: false);
  final chapterIndex = switch (chapterId) {
    null => 0,
    _ when chapterIds == null => 0,
    _ => chapterIds.indexOf(chapterId) + 1,
  };
  final resolvedChapterIndex = chapterIndex < 1 ? 0 : chapterIndex;
  return History.fromModel(
    model: model,
    ep: resolvedChapterIndex,
    page: canonicalActiveTab?.currentPageIndex ?? 0,
  );
}

Res<SourceRef> resolveReaderLoadSourceRef({
  required String comicId,
  SourceRef? explicitSourceRef,
  SourceRef? resumeSourceRef,
  String? sourceKey,
  required bool Function(String sourceKey) sourceExists,
}) {
  final resolved = resolveReaderOpenSourceRef(
    comicId: comicId,
    explicitSourceRef: explicitSourceRef,
    resumeSourceRef: resumeSourceRef,
    sourceKey: sourceKey,
  );
  if (resolved == null) {
    return const Res.error("SOURCE_REF_NOT_FOUND");
  }
  if (resolved.type == SourceRefType.remote &&
      !sourceExists(resolved.sourceKey)) {
    return Res.error("SOURCE_NOT_AVAILABLE:${resolved.sourceKey}");
  }
  return Res(resolved);
}

SourceRef? resolveReaderDiagnosticSourceRef({
  SourceRef? readerPropsSourceRef,
  SourceRef? resolvedSourceRefForDiagnostics,
  SourceRef? widgetSourceRef,
  required String comicId,
  String? sourceKey,
}) {
  return readerPropsSourceRef ??
      resolvedSourceRefForDiagnostics ??
      widgetSourceRef ??
      (sourceKey == null
          ? null
          : SourceRef.fromLegacy(comicId: comicId, sourceKey: sourceKey));
}

String buildReaderWithLoadingChildKey({
  required String comicId,
  required SourceRef sourceRef,
}) {
  return 'reader:$comicId:${sourceRef.id}';
}

class ReaderWithLoading extends StatefulWidget {
  const ReaderWithLoading({
    super.key,
    this.request,
    required this.id,
    this.sourceRef,
    this.sourceKey,
    this.initialEp,
    this.initialPage,
    this.initialGroup,
  }) : assert(request != null || sourceRef != null || sourceKey != null);

  ReaderWithLoading.fromRequest({Key? key, required ReaderOpenRequest request})
    : this(
        key: key,
        request: request,
        id: request.comicId,
        sourceRef: request.sourceRef,
        sourceKey: request.sourceKey,
        initialEp: request.initialEp,
        initialPage: request.initialPage,
        initialGroup: request.initialGroup,
      );

  final ReaderOpenRequest? request;

  final String id;

  final SourceRef? sourceRef;

  final String? sourceKey;

  final int? initialEp;

  final int? initialPage;

  final int? initialGroup;

  ReaderOpenRequest get normalizedRequest =>
      request ??
      normalizeLegacyReaderOpenRequest(
        comicId: id,
        explicitSourceRef: sourceRef,
        sourceKey: sourceKey,
        initialEp: initialEp,
        initialPage: initialPage,
        initialGroup: initialGroup,
      );

  @override
  State<ReaderWithLoading> createState() => _ReaderWithLoadingState();
}

class _ReaderWithLoadingState
    extends LoadingState<ReaderWithLoading, ReaderProps> {
  DateTime? _readerChildMountedAt;
  bool _readerChildMounted = false;
  String? _routeNameSnapshot;
  Map<String, Object?> _routeDiagnosticSnapshot = const {};
  SourceRef? _resolvedSourceRefForDiagnostics;

  SourceRef? _diagnosticSourceRef({ReaderProps? data}) {
    return resolveReaderDiagnosticSourceRef(
      readerPropsSourceRef: data?.sourceRef,
      resolvedSourceRefForDiagnostics: _resolvedSourceRefForDiagnostics,
      widgetSourceRef: widget.sourceRef,
      comicId: widget.normalizedRequest.comicId,
      sourceKey: widget.normalizedRequest.sourceKey,
    );
  }

  Future<void> _recordParentShellBuild({
    required String branch,
    required bool readerChildMounted,
    required String? routeName,
    ReaderProps? data,
  }) async {
    final sourceRef = _diagnosticSourceRef(data: data);
    if (sourceRef == null) {
      return;
    }
    final type = ComicType.fromKey(sourceRef.sourceKey);
    final chapterIds = data?.chapters?.ids;
    final runtimeContext = buildReaderRuntimeContext(
      comicId: widget.normalizedRequest.comicId,
      type: type,
      chapterIndex: data?.history.ep ?? 0,
      page: data?.history.page ?? 0,
      chapterId: chapterIds?.elementAtOrNull((data?.history.ep ?? 1) - 1),
      sourceRef: sourceRef,
    );
    final activeTab = await App.repositories.readerSession.loadActiveReaderTab(
      runtimeContext.canonicalComicId,
    );
    final diagnosticData = buildReaderParentShellDiagnosticForTesting(
      owner: 'ReaderWithLoading.buildFrame',
      branch: branch,
      readerChildMounted: readerChildMounted,
      comicId: runtimeContext.canonicalComicId,
      loadMode: runtimeContext.loadMode,
      sourceKey: runtimeContext.sourceKey,
      chapterId: runtimeContext.chapterId,
      chapterIndex: runtimeContext.chapterIndex,
      page: runtimeContext.page,
      selectedIndex: data?.history.ep,
      currentPage: data?.history.page,
      routeName: routeName,
      routeSnapshot: _routeDiagnosticSnapshot,
      expectedReaderTabId: ReaderSessionRepository.defaultTabIdForSourceRef(
        sourceRef,
      ),
      activeReaderTabId: activeTab?.tabId,
      pageOrderId: activeTab?.pageOrderId,
      requestEntrypoint: widget.normalizedRequest.diagnosticEntrypoint,
      requestCaller: widget.normalizedRequest.diagnosticCaller,
      requestSourceRefId: widget.normalizedRequest.sourceRefId,
      parentStateHash: hashCode,
      parentKey: widget.key?.toString(),
      readerChildKey: buildReaderWithLoadingChildKey(
        comicId: widget.normalizedRequest.comicId,
        sourceRef: sourceRef,
      ),
    );
    emitReaderParentShellBuildDiagnosticForTesting(diagnosticData);
  }

  Future<void> _recordParentUnmountIfRetained({
    required String reason,
    required String? routeName,
    ReaderProps? data,
  }) async {
    final mountedAt = _readerChildMountedAt;
    if (mountedAt == null) {
      return;
    }
    final openDurationMs = DateTime.now().difference(mountedAt).inMilliseconds;
    if (openDurationMs >= 5000) {
      return;
    }
    final sourceRef = _diagnosticSourceRef(data: data);
    if (sourceRef == null) {
      return;
    }
    final type = ComicType.fromKey(sourceRef.sourceKey);
    final chapterIds = data?.chapters?.ids;
    final runtimeContext = buildReaderRuntimeContext(
      comicId: widget.normalizedRequest.comicId,
      type: type,
      chapterIndex: data?.history.ep ?? 0,
      page: data?.history.page ?? 0,
      chapterId: chapterIds?.elementAtOrNull((data?.history.ep ?? 1) - 1),
      sourceRef: sourceRef,
    );
    final activeTab = await App.repositories.readerSession.loadActiveReaderTab(
      runtimeContext.canonicalComicId,
    );
    final expectedReaderTabId =
        ReaderSessionRepository.defaultTabIdForSourceRef(sourceRef);
    if (activeTab?.tabId != expectedReaderTabId) {
      return;
    }
    emitReaderParentUnmountDiagnosticForTesting(
      buildReaderParentShellDiagnosticForTesting(
        owner: 'ReaderWithLoading.parentUnmount',
        branch: error != null ? 'error' : (isLoading ? 'loading' : 'content'),
        readerChildMounted: false,
        comicId: runtimeContext.canonicalComicId,
        loadMode: runtimeContext.loadMode,
        sourceKey: runtimeContext.sourceKey,
        chapterId: runtimeContext.chapterId,
        chapterIndex: runtimeContext.chapterIndex,
        page: runtimeContext.page,
        selectedIndex: data?.history.ep,
        currentPage: data?.history.page,
        routeName: routeName,
        routeSnapshot: _routeDiagnosticSnapshot,
        expectedReaderTabId: expectedReaderTabId,
        activeReaderTabId: activeTab?.tabId,
        pageOrderId: activeTab?.pageOrderId,
        requestEntrypoint: widget.normalizedRequest.diagnosticEntrypoint,
        requestCaller: widget.normalizedRequest.diagnosticCaller,
        requestSourceRefId: widget.normalizedRequest.sourceRefId,
        parentStateHash: hashCode,
        parentKey: widget.key?.toString(),
        readerChildKey: buildReaderWithLoadingChildKey(
          comicId: widget.normalizedRequest.comicId,
          sourceRef: sourceRef,
        ),
        reason: reason,
        openDurationMs: openDurationMs,
      ),
    );
  }

  @override
  void dispose() {
    if (_readerChildMounted) {
      unawaited(
        _recordParentUnmountIfRetained(
          reason: 'parentState.dispose',
          routeName: _routeNameSnapshot,
          data: data,
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context, ReaderProps data) {
    if (!_readerChildMounted) {
      _readerChildMounted = true;
      _readerChildMountedAt = DateTime.now();
    }
    final request = widget.normalizedRequest;
    final initialPosition = resolveReaderInitialPosition(
      requestedEp: request.initialEp,
      requestedPage: request.initialPage,
      requestedGroup: request.initialGroup,
      historyEp: data.history.ep,
      historyPage: data.history.page,
      historyGroup: data.history.group,
    );
    return Reader(
      key: ValueKey(
        buildReaderWithLoadingChildKey(
          comicId: request.comicId,
          sourceRef: data.sourceRef,
        ),
      ),
      type: data.type,
      cid: data.cid,
      name: data.name,
      chapters: data.chapters,
      history: data.history,
      initialChapter: initialPosition.chapter,
      initialPage: initialPosition.page,
      initialChapterGroup: initialPosition.group,
      sourceRef: data.sourceRef,
      author: data.author,
      tags: data.tags,
    );
  }

  @override
  Widget? buildFrame(BuildContext context, Widget child) {
    final route = ModalRoute.of(context);
    _routeNameSnapshot = route?.settings.name;
    final routeHash = route?.hashCode;
    final hostDiagnostic = navigatorPushHostDiagnosticForRouteHash(routeHash);
    final lifecycleDiagnostic = navigatorLifecycleDiagnosticForRouteHash(
      routeHash,
    );
    _routeDiagnosticSnapshot = buildReaderRouteDiagnosticSnapshotForTesting(
      routeHash: routeHash,
      routeName: _routeNameSnapshot,
      routeSettingsName: route?.settings.name,
      routeSettingsArgumentsType: route?.settings.arguments?.runtimeType
          .toString(),
      routeRuntimeType: route?.runtimeType.toString(),
      routeDiagnosticIdentity: route is AppPageRoute
          ? route.diagnosticIdentity
          : null,
      navigatorHash: hostDiagnostic?['navigatorHash'] as int?,
      rootNavigatorHash: hostDiagnostic?['rootNavigatorHash'] as int?,
      nearestNavigatorHash: hostDiagnostic?['nearestNavigatorHash'] as int?,
      mainNavigatorHash: hostDiagnostic?['mainNavigatorHash'] as int?,
      rootNavigator: hostDiagnostic?['rootNavigator'] as bool?,
      nestedNavigator: hostDiagnostic?['nestedNavigator'] as bool?,
      observerAttached: hostDiagnostic?['observerAttached'],
      navigatorRole: hostDiagnostic?['navigatorRole'] as String?,
      observerStatus: lifecycleDiagnostic == null
          ? 'observer_miss'
          : 'observer_seen',
      previousRouteHash: hostDiagnostic?['previousRouteHash'] as int?,
      previousRouteDiagnosticIdentity:
          hostDiagnostic?['previousRouteDiagnosticIdentity'] as String?,
      navigatorLifecycleEvent: lifecycleDiagnostic?['event'] as String?,
    );
    final branch = isLoading
        ? 'loading'
        : (error != null ? 'error' : 'content');
    final nextReaderChildMounted = branch == 'content';
    if (_readerChildMounted && !nextReaderChildMounted) {
      unawaited(
        _recordParentUnmountIfRetained(
          reason: 'branch_switched_$branch',
          routeName: _routeNameSnapshot,
          data: data,
        ),
      );
      _readerChildMounted = false;
      _readerChildMountedAt = null;
    }
    unawaited(
      _recordParentShellBuild(
        branch: branch,
        readerChildMounted: nextReaderChildMounted,
        routeName: _routeNameSnapshot,
        data: data,
      ),
    );
    return null;
  }

  @override
  Future<Res<ReaderProps>> loadData() async {
    final request = widget.normalizedRequest;
    final sourceKey = request.sourceKey;
    final resumeSourceRef = sourceKey == null
        ? null
        : await ReaderResumeService(
            readerSessions: App.repositories.readerSession,
            loadLegacyResumeSourceRef: HistoryManager().findResumeSourceRef,
          ).loadPreferredResumeSourceRef(
            request.comicId,
            ComicType.fromKey(sourceKey),
          );
    final resolvedRefResult = resolveReaderLoadSourceRef(
      comicId: request.comicId,
      explicitSourceRef: request.sourceRef,
      resumeSourceRef: resumeSourceRef,
      sourceKey: sourceKey,
      sourceExists: (sourceKey) => ComicSource.find(sourceKey) != null,
    );
    if (resolvedRefResult.error) {
      return Res.error(resolvedRefResult.errorMessage!);
    }
    final resolvedSourceRef = resolvedRefResult.data;
    _resolvedSourceRefForDiagnostics = resolvedSourceRef;
    final type = ComicType.fromKey(resolvedSourceRef.sourceKey);
    final readerSessions = App.repositories.readerSession;
    final canonicalComicId = buildReaderRuntimeContext(
      comicId: request.comicId,
      type: type,
      chapterIndex: 0,
      page: 0,
      chapterId: null,
      sourceRef: resolvedSourceRef,
    ).canonicalComicId;
    final canonicalActiveTab = await readerSessions.loadActiveReaderTab(
      canonicalComicId,
    );
    AppDiagnostics.trace(
      'reader.lifecycle',
      'reader.open.boundary.resolved',
      data: {
        'comicId': canonicalComicId,
        'requestedComicId': request.comicId,
        'loadMode': resolvedSourceRef.type == SourceRefType.local
            ? 'local'
            : 'remote',
        'sourceKey': resolvedSourceRef.sourceKey,
        'requestSourceRefId': request.sourceRefId,
        'sourceRefId': resolvedSourceRef.id,
        'sourceRefType': resolvedSourceRef.type.key,
        'sourceRefRouteKey': resolvedSourceRef.routeKey,
        'expectedReaderTabId': ReaderSessionRepository.defaultTabIdForSourceRef(
          resolvedSourceRef,
        ),
        'activeReaderTabId': canonicalActiveTab?.tabId,
        'activeTabChapterId': canonicalActiveTab?.currentChapterId,
        'activeTabPageIndex': canonicalActiveTab?.currentPageIndex,
        'activeTabLoadMode': canonicalActiveTab?.loadMode.name,
        'activeTabPageOrderId': canonicalActiveTab?.pageOrderId,
        'activeTabIsActive': canonicalActiveTab?.isActive,
      },
    );

    if (resolvedSourceRef.type == SourceRefType.local) {
      final localDetail = await UnifiedLocalComicDetailRepository(
        store: App.repositories.comicDetailStore,
      ).getComicDetail(request.comicId);
      if (localDetail == null) {
        return Res.error("LOCAL_ASSET_MISSING");
      }
      final chapters = buildCanonicalReaderChapters(localDetail.chapters);
      return Res(
        ReaderProps(
          type: type,
          cid: request.comicId,
          name: localDetail.title,
          chapters: chapters,
          history: buildReaderCompatibilityHistory(
            model: _CanonicalReaderHistoryModel(
              title: localDetail.title,
              subTitle: localDetail.primarySource?.sourceTitle,
              cover: localDetail.coverLocalPath ?? '',
              id: request.comicId,
              historyType: type,
            ),
            chapters: chapters,
            canonicalActiveTab: canonicalActiveTab,
          ),
          sourceRef: resolvedSourceRef,
          author: localDetail.primarySource?.sourceTitle ?? '',
          tags: buildCanonicalReaderTags(localDetail),
        ),
      );
    }

    final comicSource = ComicSource.find(resolvedSourceRef.sourceKey);
    if (comicSource == null) {
      return Res.error("SOURCE_NOT_AVAILABLE:${resolvedSourceRef.sourceKey}");
    }
    try {
      SourceIdentityPolicy.assertAdapterSafe(resolvedSourceRef);
    } on SourceIdentityError catch (e) {
      return Res.error("SOURCE_IDENTITY_ERROR:${e.codeKey}");
    }

    final comic = await comicSource.loadComicInfo!(resolvedSourceRef.refId);
    if (comic.error) {
      return Res.fromErrorRes(comic);
    }
    return Res(
      ReaderProps(
        type: type,
        cid: request.comicId,
        name: comic.data.title,
        chapters: comic.data.chapters,
        history: buildReaderCompatibilityHistory(
          model: comic.data,
          chapters: comic.data.chapters,
          canonicalActiveTab: canonicalActiveTab,
        ),
        sourceRef: resolvedSourceRef,
        author: comic.data.findAuthor() ?? "",
        tags: comic.data.plainTags,
      ),
    );
  }
}

class ReaderProps {
  final ComicType type;

  final String cid;

  final String name;

  final ComicChapters? chapters;

  final History history;

  final SourceRef sourceRef;

  final String author;

  final List<String> tags;

  const ReaderProps({
    required this.type,
    required this.cid,
    required this.name,
    required this.chapters,
    required this.history,
    required this.sourceRef,
    required this.author,
    required this.tags,
  });
}
