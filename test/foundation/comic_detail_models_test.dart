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
