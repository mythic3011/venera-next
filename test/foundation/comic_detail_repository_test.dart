import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_detail/comic_detail.dart';

void main() {
  test('static repository returns mapped detail for comic id', () async {
    final repository = StaticComicDetailRepository({
      'comic-1': ComicDetailViewModel.scaffold(
        comicId: 'comic-1',
        title: 'Mapped',
        libraryState: LibraryState.downloaded,
      ),
    });

    final detail = await repository.getComicDetail('comic-1');

    expect(detail, isNotNull);
    expect(detail!.title, 'Mapped');
    expect(detail.libraryState, LibraryState.downloaded);
  });

  test(
    'composite repository returns first non-null detail from loaders',
    () async {
      final calls = <String>[];
      final repository = CompositeComicDetailRepository(
        loaders: [
          (comicId) async {
            calls.add('first:$comicId');
            return null;
          },
          (comicId) async {
            calls.add('second:$comicId');
            return ComicDetailViewModel.scaffold(
              comicId: comicId,
              title: 'Resolved',
              libraryState: LibraryState.localWithRemoteSource,
            );
          },
          (comicId) async {
            calls.add('third:$comicId');
            return ComicDetailViewModel.scaffold(
              comicId: comicId,
              title: 'Unexpected',
              libraryState: LibraryState.unavailable,
            );
          },
        ],
      );

      final detail = await repository.getComicDetail('comic-9');

      expect(detail, isNotNull);
      expect(detail!.title, 'Resolved');
      expect(calls, ['first:comic-9', 'second:comic-9']);
    },
  );

  test(
    'stub repository provides conservative unavailable placeholder',
    () async {
      const repository = StubComicDetailRepository();

      final detail = await repository.getComicDetail('missing-comic');

      expect(detail, isNotNull);
      expect(detail!.comicId, 'missing-comic');
      expect(detail.title, 'missing-comic');
      expect(detail.libraryState, LibraryState.unavailable);
      expect(detail.availableActions.hasAnyAction, isFalse);
    },
  );
}
