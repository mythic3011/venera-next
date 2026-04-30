part of 'reader.dart';

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
  return SourceRef.fromLegacy(
    comicId: comicId,
    sourceKey: key,
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
  if (resolved.type == SourceRefType.remote && !sourceExists(resolved.sourceKey)) {
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
  @override
  Widget buildContent(BuildContext context, ReaderProps data) {
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
  Future<Res<ReaderProps>> loadData() async {
    final sourceKey = widget.sourceKey;
    final resumeSourceRef = sourceKey == null
        ? null
        : await HistoryManager().loadPreferredResumeSourceRef(
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
    final history = HistoryManager().find(
      widget.id,
      type,
    );

    if (resolvedSourceRef.type == SourceRefType.local) {
      final localComic = LocalManager().find(
        widget.id,
        type,
      );
      if (localComic == null) {
        return Res.error("LOCAL_ASSET_MISSING");
      }
      return Res(
        ReaderProps(
          type: type,
          cid: widget.id,
          name: localComic.title,
          chapters: localComic.chapters,
          history: history ??
              History.fromModel(
                model: localComic,
                ep: 0,
                page: 0,
              ),
          sourceRef: resolvedSourceRef,
          author: localComic.subtitle,
          tags: localComic.tags,
        ),
      );
    }

    final comicSource = ComicSource.find(resolvedSourceRef.sourceKey);
    if (comicSource == null) {
      return Res.error("SOURCE_NOT_AVAILABLE:${resolvedSourceRef.sourceKey}");
    }

    final comic = await comicSource.loadComicInfo!(widget.id);
    if (comic.error) {
      return Res.fromErrorRes(comic);
    }
    return Res(
      ReaderProps(
        type: type,
        cid: widget.id,
        name: comic.data.title,
        chapters: comic.data.chapters,
        history: history ??
            History.fromModel(
              model: comic.data,
              ep: 0,
              page: 0,
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
