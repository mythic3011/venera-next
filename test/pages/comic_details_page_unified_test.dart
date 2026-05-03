import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/source_ref.dart';
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

  test('local detail chapter read resolves imported chapter SourceRef', () {
    final chapters = ComicChapters({
      '1:__imported__': 'Imported Chapter',
      '2:__imported__': 'Imported Chapter 2',
    });

    final sourceRef = resolveComicDetailsReadSourceRef(
      comicId: 'comic-local',
      sourceKey: 'local',
      chapters: chapters,
      ep: 1,
      group: null,
      resumeSourceRef: null,
    );

    expect(sourceRef.type, SourceRefType.local);
    expect(sourceRef.sourceKey, 'local');
    expect(sourceRef.params['chapterId'], '1:__imported__');
  });

  test('local detail read bypasses reader next bridge', () {
    expect(
      shouldBypassReaderNextForComicDetailRead(sourceKey: 'local'),
      isTrue,
    );
    expect(
      shouldBypassReaderNextForComicDetailRead(sourceKey: 'nhentai'),
      isFalse,
    );
  });

  test('local detail read request uses resolved local imported sourceRef', () {
    final sourceRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-local',
      chapterId: '1:__imported__',
    );
    final request = buildComicDetailReaderOpenRequest(
      comic: ComicDetails.fromJson({
        'title': 'Local Comic',
        'sourceKey': 'local',
        'comicId': 'comic-local',
      }),
      sourceRef: sourceRef,
      ep: 1,
      page: 2,
      group: null,
    );

    expect(request.comicId, 'comic-local');
    expect(request.sourceRef.id, 'local:local:comic-local:1:__imported__');
    expect(request.sourceKey, 'local');
    expect(request.chapterRefId, '1:__imported__');
  });

  test('local detail read request does not fall back to placeholder chapter id', () {
    final sourceRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-local',
      chapterId: '1:__imported__',
    );
    final request = buildComicDetailReaderOpenRequest(
      comic: ComicDetails.fromJson({
        'title': 'Local Comic',
        'sourceKey': 'local',
        'comicId': 'comic-local',
      }),
      sourceRef: sourceRef,
      ep: 1,
      page: 1,
      group: null,
    );

    expect(request.sourceRef.id, isNot('local:local:comic-local:_'));
    expect(request.chapterRefId, isNot('_'));
  });
}
