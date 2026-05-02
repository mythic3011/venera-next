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

class ReaderWithLoading extends StatefulWidget {
  const ReaderWithLoading({
    super.key,
    required this.id,
    this.sourceRef,
    this.sourceKey,
    this.initialEp,
    this.initialPage,
    this.initialGroup,
  }) : assert(sourceRef != null || sourceKey != null);

  final String id;

  final SourceRef? sourceRef;

  final String? sourceKey;

  final int? initialEp;

  final int? initialPage;

  final int? initialGroup;

  @override
  State<ReaderWithLoading> createState() => _ReaderWithLoadingState();
}

class _ReaderWithLoadingState
    extends LoadingState<ReaderWithLoading, ReaderProps> {
  DateTime? _readerChildMountedAt;
  bool _readerChildMounted = false;
  String? _routeNameSnapshot;

  SourceRef? _diagnosticSourceRef({ReaderProps? data}) {
    return data?.sourceRef ??
        widget.sourceRef ??
        (widget.sourceKey == null
            ? null
            : SourceRef.fromLegacy(
                comicId: widget.id,
                sourceKey: widget.sourceKey!,
              ));
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
      comicId: widget.id,
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
      expectedReaderTabId: ReaderSessionRepository.defaultTabIdForSourceRef(
        sourceRef,
      ),
      activeReaderTabId: activeTab?.tabId,
      pageOrderId: activeTab?.pageOrderId,
      parentKey: widget.key?.toString(),
      readerChildKey: 'reader:${widget.id}:${sourceRef.id}',
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
      comicId: widget.id,
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
        expectedReaderTabId: expectedReaderTabId,
        activeReaderTabId: activeTab?.tabId,
        pageOrderId: activeTab?.pageOrderId,
        parentKey: widget.key?.toString(),
        readerChildKey: 'reader:${widget.id}:${sourceRef.id}',
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
    final initialPosition = resolveReaderInitialPosition(
      requestedEp: widget.initialEp,
      requestedPage: widget.initialPage,
      requestedGroup: widget.initialGroup,
      historyEp: data.history.ep,
      historyPage: data.history.page,
      historyGroup: data.history.group,
    );
    return Reader(
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
    _routeNameSnapshot = ModalRoute.of(context)?.settings.name;
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
    final sourceKey = widget.sourceKey;
    final resumeSourceRef = sourceKey == null
        ? null
        : await ReaderResumeService(
            readerSessions: App.repositories.readerSession,
          ).loadPreferredResumeSourceRef(
            widget.id,
            ComicType.fromKey(sourceKey),
          );
    final resolvedRefResult = resolveReaderLoadSourceRef(
      comicId: widget.id,
      explicitSourceRef: widget.sourceRef,
      resumeSourceRef: resumeSourceRef,
      sourceKey: sourceKey,
      sourceExists: (sourceKey) => ComicSource.find(sourceKey) != null,
    );
    if (resolvedRefResult.error) {
      return Res.error(resolvedRefResult.errorMessage!);
    }
    final resolvedSourceRef = resolvedRefResult.data;
    final type = ComicType.fromKey(resolvedSourceRef.sourceKey);
    final readerSessions = App.repositories.readerSession;
    final canonicalComicId = buildReaderRuntimeContext(
      comicId: widget.id,
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
        'requestedComicId': widget.id,
        'loadMode': resolvedSourceRef.type == SourceRefType.local
            ? 'local'
            : 'remote',
        'sourceKey': resolvedSourceRef.sourceKey,
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
      ).getComicDetail(widget.id);
      if (localDetail == null) {
        return Res.error("LOCAL_ASSET_MISSING");
      }
      final chapters = buildCanonicalReaderChapters(localDetail.chapters);
      return Res(
        ReaderProps(
          type: type,
          cid: widget.id,
          name: localDetail.title,
          chapters: chapters,
          history: buildReaderCompatibilityHistory(
            model: _CanonicalReaderHistoryModel(
              title: localDetail.title,
              subTitle: localDetail.primarySource?.sourceTitle,
              cover: localDetail.coverLocalPath ?? '',
              id: widget.id,
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
        cid: widget.id,
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
