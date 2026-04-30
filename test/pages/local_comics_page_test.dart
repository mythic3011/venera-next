import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/local_comics_page.dart';

void main() {
  final comicA = LocalComic(
    id: 'comic-a',
    title: 'Legacy Alpha',
    subtitle: '',
    tags: <String>['legacy'],
    directory: '/tmp/a',
    chapters: null,
    cover: 'cover.jpg',
    comicType: ComicType.local,
    downloadedChapters: <String>[],
    createdAt: DateTime.utc(2026, 4, 29),
  );
  final comicB = LocalComic(
    id: 'comic-b',
    title: 'Legacy Beta',
    subtitle: '',
    tags: <String>['legacy'],
    directory: '/tmp/b',
    chapters: null,
    cover: 'cover.jpg',
    comicType: ComicType.local,
    downloadedChapters: <String>[],
    createdAt: DateTime.utc(2026, 4, 28),
  );

  test('canonical local library view sorts by canonical updated time', () {
    final visible = applyCanonicalLocalLibraryView(
      comics: [comicA, comicB],
      browseRecords: const [
        LocalLibraryBrowseItem(
          comicId: 'comic-a',
          title: 'Legacy Alpha',
          updatedAt: '2026-04-29T09:00:00.000Z',
          userTags: <String>[],
          sourceTags: <String>[],
        ),
        LocalLibraryBrowseItem(
          comicId: 'comic-b',
          title: 'Legacy Beta',
          updatedAt: '2026-04-30T09:00:00.000Z',
          userTags: <String>[],
          sourceTags: <String>[],
        ),
      ],
      sortType: LocalSortType.timeDesc,
    );

    expect(visible.map((comic) => comic.id), ['comic-b', 'comic-a']);
  });

  test(
    'canonical local library view searches canonical user and source tags',
    () {
      final visible = applyCanonicalLocalLibraryView(
        comics: [comicA, comicB],
        browseRecords: const [
          LocalLibraryBrowseItem(
            comicId: 'comic-a',
            title: 'Legacy Alpha',
            userTags: <String>['queued'],
            sourceTags: <String>[],
          ),
          LocalLibraryBrowseItem(
            comicId: 'comic-b',
            title: 'Legacy Beta',
            userTags: <String>[],
            sourceTags: <String>['female:glasses'],
          ),
        ],
        sortType: LocalSortType.name,
        keyword: 'glasses',
      );

      expect(visible.map((comic) => comic.id), ['comic-b']);
    },
  );

  test('local detail entry uses canonical comic id route', () {
    final page = buildLocalComicDetailEntry(comicA);

    expect(page, isA<ComicDetailPage>());
    expect(page.comicId, 'comic-a');
    expect(page.id, 'comic-a');
    expect(page.sourceKey, localSourceKey);
    expect(page.title, 'Legacy Alpha');
  });

  test('local chapter labels use order and title without raw ids', () {
    final label = formatLocalChapterDisplayLabel(
      index: 1,
      title: 'Imported Chapter',
    );

    expect(label, '2. Imported Chapter');
    expect(label, isNot(contains('chapter-raw-id')));
  });
}
