import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

void main() {
  final localComic = LocalComic(
    id: 'comic-local',
    title: 'Local Comic',
    subtitle: 'Imported',
    tags: <String>['legacy:tag'],
    directory: '/tmp/local-comic',
    chapters: null,
    cover: 'cover.jpg',
    comicType: ComicType.local,
    downloadedChapters: <String>[],
    createdAt: DateTime.utc(2026, 4, 30),
  );

  test('local canonical detail renders not-linked remote source label', () {
    final detail = ComicDetailViewModel.scaffold(
      comicId: 'comic-local',
      title: 'Local Comic',
      libraryState: LibraryState.localOnly,
    );

    final rendered = buildLocalDetailsFromCanonicalForTesting(detail, localComic);

    expect(rendered.subTitle, contains('Remote source: Not linked'));
    expect(rendered.tags['legacy'], ['tag']);
  });

  test('local canonical detail keeps source tags and user tags separated', () {
    const platform = SourcePlatformRef(
      platformId: 'copymanga',
      canonicalKey: 'copymanga',
      displayName: 'CopyManga',
      kind: SourcePlatformKind.remote,
      matchedAlias: 'copymanga',
      matchedAliasType: SourceAliasType.canonical,
    );
    final detail = ComicDetailViewModel(
      comicId: 'comic-local',
      title: 'Local Comic',
      libraryState: LibraryState.localWithRemoteSource,
      primarySource: const ComicSourceCitation(
        platform: platform,
        relationType: 'active',
        comicUrl: 'https://example.com/comic/1',
        sourceTitle: 'Remote Title',
      ),
      sourceTags: const [
        SourceTagVm(
          id: 'source-tag-1',
          name: 'glasses',
          namespace: 'female',
          platform: platform,
        ),
      ],
      userTags: const [
        ComicTagVm(id: 'user-tag-1', name: 'queued'),
      ],
    );

    final rendered = buildLocalDetailsFromCanonicalForTesting(detail, localComic);

    expect(rendered.subTitle, contains('Remote source: CopyManga'));
    expect(rendered.url, 'https://example.com/comic/1');
    expect(rendered.tags['female'], ['glasses']);
    expect(rendered.tags['User Tags'], ['queued']);
  });

  test('continue action is capability gated by canonical detail state', () {
    final history = History.fromModel(model: localComic, ep: 1, page: 1);
    final noContinue = ComicDetailViewModel.scaffold(
      comicId: 'comic-local',
      title: 'Local Comic',
      libraryState: LibraryState.localOnly,
    );
    final canContinue = ComicDetailViewModel.scaffold(
      comicId: 'comic-local',
      title: 'Local Comic',
      libraryState: LibraryState.localOnly,
      availableActions: const ComicDetailActions(canContinueReading: true),
    );

    expect(
      comicPageHasContinueActionForTesting(
        canonicalDetail: noContinue,
        history: history,
      ),
      isFalse,
    );
    expect(
      comicPageHasContinueActionForTesting(
        canonicalDetail: canContinue,
        history: history,
      ),
      isTrue,
    );
  });
}
