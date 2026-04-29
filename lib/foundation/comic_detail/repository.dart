import 'models.dart';

typedef ComicDetailLoader =
    Future<ComicDetailViewModel?> Function(String comicId);

abstract class ComicDetailRepository {
  Future<ComicDetailViewModel?> getComicDetail(String comicId);
}

class StaticComicDetailRepository implements ComicDetailRepository {
  const StaticComicDetailRepository(this.records);

  final Map<String, ComicDetailViewModel> records;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    return records[comicId];
  }
}

class CompositeComicDetailRepository implements ComicDetailRepository {
  const CompositeComicDetailRepository({required this.loaders});

  final List<ComicDetailLoader> loaders;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    for (final loader in loaders) {
      final detail = await loader(comicId);
      if (detail != null) {
        return detail;
      }
    }
    return null;
  }
}

class StubComicDetailRepository implements ComicDetailRepository {
  const StubComicDetailRepository({
    this.missingState = LibraryState.unavailable,
  });

  final LibraryState missingState;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    return ComicDetailViewModel.scaffold(
      comicId: comicId,
      title: comicId,
      libraryState: missingState,
    );
  }
}
