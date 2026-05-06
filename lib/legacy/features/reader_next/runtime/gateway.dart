import 'adapter.dart';
import 'models.dart';
import 'registry.dart';

class RemoteAdapterGateway {
  RemoteAdapterGateway(this._registry);

  final SourceRegistry _registry;

  ExternalSourceAdapter _requireRemoteAdapter(SourceRef sourceRef) {
    if (!sourceRef.isRemote) {
      throw ReaderRuntimeException(
        'SOURCE_REF_REQUIRED',
        'Remote operation requires remote SourceRef',
      );
    }
    if (sourceRef.upstreamComicRefId.contains(':')) {
      throw ReaderRuntimeException(
        'UPSTREAM_ID_INVALID',
        'Adapter must not receive canonical IDs',
      );
    }
    return _registry.requireAdapter(sourceRef.sourceKey);
  }

  Future<List<SearchResultItem>> search({
    required String sourceKey,
    required SearchQuery query,
  }) {
    final adapter = _registry.requireAdapter(sourceKey);
    return adapter.search(query: query);
  }

  Future<ComicDetailResult> loadComicDetail({
    required ComicIdentity identity,
  }) {
    identity.assertRemoteOperationSafe();
    final adapter = _requireRemoteAdapter(identity.sourceRef);
    return adapter.loadComicDetail(
      upstreamComicRefId: identity.sourceRef.upstreamComicRefId,
    );
  }

  Future<List<ReaderImageRef>> loadReaderPageImages({
    required ComicIdentity identity,
    required String chapterRefId,
    required int page,
  }) {
    identity.assertRemoteOperationSafe();
    if (chapterRefId.isEmpty) {
      throw ReaderRuntimeException('CHAPTER_REF_INVALID', 'chapterRefId is required');
    }
    final adapter = _requireRemoteAdapter(identity.sourceRef);
    return adapter.loadReaderPageImages(
      upstreamComicRefId: identity.sourceRef.upstreamComicRefId,
      chapterRefId: chapterRefId,
      page: page,
    );
  }
}
