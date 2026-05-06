import 'package:venera/foundation/diagnostics/diagnostics.dart';

import 'cache_keys.dart';
import 'gateway.dart';
import 'local_resolver.dart';
import 'models.dart';
import 'ports.dart';
import 'session.dart';

class ReaderNextRuntime {
  ReaderNextRuntime({
    required RemoteAdapterGateway gateway,
    required ReaderSessionStore sessionStore,
    ImageCacheStore imageCacheStore = const NoopImageCacheStore(),
    LocalReaderPageResolver localPageResolver =
        const LegacyLocalReaderPageResolver(),
  }) : _gateway = gateway,
       _sessionStore = sessionStore,
       _imageCacheStore = imageCacheStore,
       _localPageResolver = localPageResolver;

  final RemoteAdapterGateway _gateway;
  final ReaderSessionStore _sessionStore;
  final ImageCacheStore _imageCacheStore;
  final LocalReaderPageResolver _localPageResolver;

  Future<List<SearchResultItem>> search({
    required String sourceKey,
    required String keyword,
    int page = 1,
  }) {
    if (sourceKey.isEmpty || keyword.trim().isEmpty) {
      throw ReaderRuntimeException(
        'SEARCH_INVALID',
        'sourceKey and keyword are required',
      );
    }
    return _gateway.search(
      sourceKey: sourceKey,
      query: SearchQuery(keyword: keyword.trim(), page: page),
    );
  }

  Future<ComicDetailResult> loadComicDetail({required ComicIdentity identity}) {
    return _gateway.loadComicDetail(identity: identity);
  }

  Future<List<ReaderImageRefWithCacheKey>> loadReaderPage({
    required ComicIdentity identity,
    required String chapterRefId,
    required int page,
    String? pageOrderId,
  }) async {
    final isRemote = identity.sourceRef.isRemote;
    if (!isRemote && (pageOrderId == null || pageOrderId.trim().isEmpty)) {
      AppDiagnostics.info(
        'reader.local',
        'reader.local.resume.pageOrderFallback',
        data: {
          'loadMode': 'local',
          'sourceKey': identity.sourceRef.sourceKey,
          'comicId': identity.canonicalComicId,
          'chapterId': chapterRefId,
          'page': page,
          'pageOrderId': pageOrderId,
          'fallback': 'currentPageIndex:fileOrder',
        },
      );
    }
    final images = isRemote
        ? await _gateway.loadReaderPageImages(
            identity: identity,
            chapterRefId: chapterRefId,
            page: page,
          )
        : await _localPageResolver.loadReaderPageImages(
            identity: identity,
            chapterRefId: chapterRefId,
            page: page,
          );

    if (images.isEmpty) {
      throw ReaderRuntimeException(
        isRemote ? 'REMOTE_PAGES_EMPTY' : 'LOCAL_PAGES_EMPTY',
        isRemote
            ? 'Remote chapter has no renderable pages'
            : 'Local chapter has no renderable pages',
      );
    }

    if (isRemote) {
      return images
          .map(
            (image) => ReaderImageRefWithCacheKey(
              image: image,
              cacheKey: buildReaderImageCacheKey(
                sourceRef: identity.sourceRef,
                canonicalComicId: identity.canonicalComicId,
                upstreamComicRefId: identity.sourceRef.upstreamComicRefId,
                chapterRefId: chapterRefId,
                imageKey: image.imageKey,
              ),
            ),
          )
          .toList();
    }

    return images
        .map(
          (image) => ReaderImageRefWithCacheKey(
            image: image,
            cacheKey: [
              identity.sourceRef.sourceKey,
              identity.canonicalComicId,
              identity.sourceRef.upstreamComicRefId,
              chapterRefId,
              image.imageKey,
            ].join('@'),
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveResumeSession({
    required ComicIdentity identity,
    required String chapterRefId,
    required int page,
    String? pageOrderId,
  }) {
    final session = ReaderResumeSession(
      canonicalComicId: identity.canonicalComicId,
      sourceRef: identity.sourceRef,
      chapterRefId: chapterRefId,
      page: page,
      pageOrderId: pageOrderId,
    );
    return _sessionStore.save(session);
  }

  Future<ReaderResumeSession?> loadResumeSession({
    required String canonicalComicId,
  }) {
    if (!canonicalComicId.contains(':')) {
      throw ReaderRuntimeException(
        'CANONICAL_ID_INVALID',
        'Resume lookup requires namespaced canonicalComicId',
      );
    }
    return _sessionStore.load(canonicalComicId: canonicalComicId);
  }

  Future<ReaderImageBytesResult> loadImageBytes({
    required ReaderImageRefWithCacheKey imageWithCacheKey,
    required Future<List<int>> Function(ReaderImageRef image) fetchRemoteBytes,
  }) async {
    final cacheHit = await _imageCacheStore.read(
      cacheKey: imageWithCacheKey.cacheKey,
    );
    if (cacheHit != null) {
      return ReaderImageBytesResult(
        bytes: cacheHit,
        fromCache: true,
        image: imageWithCacheKey.image,
        cacheKey: imageWithCacheKey.cacheKey,
      );
    }

    final remoteBytes = await fetchRemoteBytes(imageWithCacheKey.image);
    await _imageCacheStore.write(
      cacheKey: imageWithCacheKey.cacheKey,
      bytes: remoteBytes,
    );
    return ReaderImageBytesResult(
      bytes: List<int>.from(remoteBytes),
      fromCache: false,
      image: imageWithCacheKey.image,
      cacheKey: imageWithCacheKey.cacheKey,
    );
  }
}

class ReaderImageRefWithCacheKey {
  const ReaderImageRefWithCacheKey({
    required this.image,
    required this.cacheKey,
  });

  final ReaderImageRef image;
  final String cacheKey;
}

class ReaderImageBytesResult {
  const ReaderImageBytesResult({
    required this.bytes,
    required this.fromCache,
    required this.image,
    required this.cacheKey,
  });

  final List<int> bytes;
  final bool fromCache;
  final ReaderImageRef image;
  final String cacheKey;
}
