import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_detail/comic_detail.dart';

void main() {
  test('scaffold view model defaults to empty read-only collections', () {
    final detail = ComicDetailViewModel.scaffold(
      comicId: 'comic-1',
      title: 'Demo',
      libraryState: LibraryState.localOnly,
    );

    expect(detail.comicId, 'comic-1');
    expect(detail.title, 'Demo');
    expect(detail.libraryState, LibraryState.localOnly);
    expect(detail.userTags, isEmpty);
    expect(detail.sourceTags, isEmpty);
    expect(detail.chapters, isEmpty);
    expect(detail.readerTabs, isEmpty);
    expect(detail.pageOrderSummary, PageOrderSummaryVm.empty);
    expect(detail.availableActions, ComicDetailActions.none);
    expect(detail.isReadable, isFalse);
  });

  test('view model freezes caller-owned collections', () {
    final sourceTags = <SourceTagVm>[];
    final chapters = <ChapterVm>[
      const ChapterVm(chapterId: 'chapter-1', title: 'Chapter 1'),
    ];
    final detail = ComicDetailViewModel(
      comicId: 'comic-1',
      title: 'Demo',
      libraryState: LibraryState.localOnly,
      sourceTags: sourceTags,
      chapters: chapters,
    );

    sourceTags.add(
      const SourceTagVm(
        id: 'tag-1',
        name: 'tag',
        namespace: 'meta',
        platform: SourcePlatformRef(
          platformId: 'local',
          canonicalKey: 'local',
          displayName: 'Local',
          kind: SourcePlatformKind.local,
          matchedAlias: 'local',
          matchedAliasType: SourceAliasType.canonical,
        ),
      ),
    );
    chapters.add(const ChapterVm(chapterId: 'chapter-2', title: 'Chapter 2'));

    expect(detail.sourceTags, isEmpty);
    expect(detail.chapters, hasLength(1));
    expect(
      () => detail.chapters.add(
        const ChapterVm(chapterId: 'chapter-3', title: 'Chapter 3'),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'page order summary exposes custom overlay state without mutating pages',
    () {
      const summary = PageOrderSummaryVm(
        activeOrderId: 'order-1',
        activeOrderType: PageOrderKind.userCustom,
        totalOrders: 2,
        totalPageCount: 24,
        visiblePageCount: 22,
      );

      expect(summary.hasCustomOrder, isTrue);
      expect(summary.totalOrders, 2);
      expect(summary.totalPageCount, 24);
      expect(summary.visiblePageCount, 22);
    },
  );

  test('citation keeps typed platform provenance', () {
    const platform = SourcePlatformRef(
      platformId: 'webdav-main',
      canonicalKey: 'webdav',
      displayName: 'WebDAV',
      kind: SourcePlatformKind.remote,
      matchedAlias: 'webdav-v2',
      matchedAliasType: SourceAliasType.pluginKey,
      legacyIntType: 7,
    );
    final citation = ComicSourceCitation(
      platform: platform,
      relationType: 'manual_match',
      comicUrl: 'https://example.test/comic/1',
      sourceTitle: 'Source Title',
    );

    expect(citation.platformName, 'WebDAV');
    expect(citation.platform.matchedAlias, 'webdav-v2');
    expect(citation.platform.matchedAliasType, SourceAliasType.pluginKey);
    expect(citation.platform.legacyIntType, 7);
  });

  test(
    'readable state is capability-driven instead of library-state-driven',
    () {
      const actions = ComicDetailActions(
        canOpenInNewTab: true,
        canManageUserTags: true,
      );
      final detail = ComicDetailViewModel.scaffold(
        comicId: 'comic-2',
        title: 'Remote',
        libraryState: LibraryState.remoteOnly,
        availableActions: actions,
      );

      expect(detail.isReadable, isTrue);
      expect(detail.availableActions.hasAnyAction, isTrue);
      expect(detail.availableActions.canManagePageOrder, isFalse);
    },
  );
}
