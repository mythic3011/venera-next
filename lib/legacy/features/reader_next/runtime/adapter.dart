import 'models.dart';

abstract interface class ExternalSourceAdapter {
  String get sourceKey;

  Future<List<SearchResultItem>> search({required SearchQuery query});

  Future<ComicDetailResult> loadComicDetail({
    required String upstreamComicRefId,
  });

  Future<List<ReaderImageRef>> loadReaderPageImages({
    required String upstreamComicRefId,
    required String chapterRefId,
    required int page,
  });
}
