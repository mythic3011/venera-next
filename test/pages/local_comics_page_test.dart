import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/local.dart';
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
        LocalLibraryBrowseRecord(
          comicId: 'comic-a',
          title: 'Legacy Alpha',
          normalizedTitle: 'legacy alpha',
          updatedAt: '2026-04-29T09:00:00.000Z',
        ),
        LocalLibraryBrowseRecord(
          comicId: 'comic-b',
          title: 'Legacy Beta',
          normalizedTitle: 'legacy beta',
          updatedAt: '2026-04-30T09:00:00.000Z',
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
          LocalLibraryBrowseRecord(
            comicId: 'comic-a',
            title: 'Legacy Alpha',
            normalizedTitle: 'legacy alpha',
            userTags: <String>['queued'],
          ),
          LocalLibraryBrowseRecord(
            comicId: 'comic-b',
            title: 'Legacy Beta',
            normalizedTitle: 'legacy beta',
            sourceTags: <String>['female:glasses'],
          ),
        ],
        sortType: LocalSortType.name,
        keyword: 'glasses',
      );

      expect(visible.map((comic) => comic.id), ['comic-b']);
    },
  );
}
