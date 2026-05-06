part of 'reader.dart';

class ReaderPageLoadRequest {
  const ReaderPageLoadRequest({
    required this.type,
    required this.canonicalComicRefId,
    required this.chapterIndex,
    required this.chapters,
    required this.sourceRef,
    required this.hasLocalComic,
    required this.isDownloaded,
  });

  final ComicType type;
  final String canonicalComicRefId;
  final int chapterIndex;
  final ComicChapters? chapters;
  final SourceRef? sourceRef;
  final bool hasLocalComic;
  final bool isDownloaded;
}

class ReaderPageLoadResult {
  const ReaderPageLoadResult({
    required this.loadMode,
    required this.sourceRef,
    required this.res,
    this.errorCode,
  });

  final String loadMode;
  final SourceRef? sourceRef;
  final Res<List<String>> res;
  final String? errorCode;
}

class ReaderPageLoadController {
  const ReaderPageLoadController({required this.loader});

  final ReaderPageLoader loader;

  Future<ReaderPageLoadResult> loadReaderPageList({
    required ReaderPageLoadRequest request,
    required String loadMode,
  }) async {
    late final SourceRef sourceRef;
    try {
      sourceRef = buildReaderPageLoadSourceRef(
        request: request,
        loadMode: loadMode,
      );
    } catch (error) {
      final code = error.toString().contains('SOURCE_REF_MALFORMED')
          ? 'SOURCE_REF_MALFORMED'
          : 'SOURCE_REF_INVALID';
      return ReaderPageLoadResult(
        loadMode: loadMode,
        sourceRef: null,
        res: Res.error(error.toString()),
        errorCode: code,
      );
    }
    final result = await dispatchReaderPageLoad(
      useSourceRefResolver: true,
      loadMode: loadMode,
      legacyLoadPages: () async =>
          const Res.error('SOURCE_REF_RESOLVER_REQUIRED'),
      loader: loader,
      sourceRef: sourceRef,
    );
    final emptyPageListError = resolveReaderEmptyPageListError(
      images: result.res.error ? const <String>[] : result.res.data,
      loadMode: result.loadMode,
      canonicalComicRefId: request.canonicalComicRefId,
      chapterIndex: request.chapterIndex,
      chapterId: sourceRef.params['chapterId']?.toString(),
      sourceKey: sourceRef.sourceKey,
    );
    if (!result.res.error && emptyPageListError != null) {
      return ReaderPageLoadResult(
        loadMode: result.loadMode,
        sourceRef: sourceRef,
        res: Res.error(emptyPageListError),
        errorCode: 'EMPTY_PAGE_LIST',
      );
    }
    return ReaderPageLoadResult(
      loadMode: result.loadMode,
      sourceRef: sourceRef,
      res: result.res,
      errorCode: result.res.error ? result.res.errorMessage : null,
    );
  }
}

String decideReaderPageLoadMode(ReaderPageLoadRequest request) {
  return _shouldLoadReaderPagesLocally(
        type: request.type,
        canonicalComicRefId: request.canonicalComicRefId,
        isDownloaded: (_, __) => request.isDownloaded,
        hasLocalComic: (_) => request.hasLocalComic,
      )
      ? 'local'
      : 'remote';
}

SourceRef buildReaderPageLoadSourceRef({
  required ReaderPageLoadRequest request,
  required String loadMode,
}) {
  final chapterId =
      request.chapters?.ids.elementAtOrNull(request.chapterIndex - 1) ??
      (loadMode == 'local' ? null : request.chapterIndex.toString());
  final existingRef = request.sourceRef;
  if (existingRef != null) {
    final existingChapterId = existingRef.params['chapterId']?.toString();
    if (existingChapterId == chapterId) {
      return existingRef;
    }
    return switch (existingRef.type) {
      SourceRefType.local => SourceRef.fromLegacyLocal(
        localType:
            existingRef.params['localType']?.toString() ?? localSourceKey,
        localComicId:
            existingRef.params['localComicId']?.toString() ??
            request.canonicalComicRefId,
        chapterId: chapterId,
      ),
      SourceRefType.remote => SourceRef.fromLegacyRemote(
        sourceKey: existingRef.sourceKey,
        comicId: requireRemoteUpstreamComicRefId(existingRef),
        chapterId: chapterId,
        routeKey: existingRef.routeKey,
      ),
    };
  }
  if (loadMode == 'local') {
    return SourceRef.fromLegacyLocal(
      localType: _readerLocalTypeKey(
        type: request.type,
        canonicalComicRefId: request.canonicalComicRefId,
        hasLocalComic: (_) => request.hasLocalComic,
      ),
      localComicId: request.canonicalComicRefId,
      chapterId: chapterId,
    );
  }
  throw StateError('REMOTE_READER_REQUIRES_SOURCE_REF');
}

@visibleForTesting
String decideReaderPageLoadModeForTesting(ReaderPageLoadRequest request) {
  return decideReaderPageLoadMode(request);
}

@visibleForTesting
SourceRef buildReaderPageLoadSourceRefForTesting({
  required ReaderPageLoadRequest request,
  required String loadMode,
}) {
  return buildReaderPageLoadSourceRef(request: request, loadMode: loadMode);
}
