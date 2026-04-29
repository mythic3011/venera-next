import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

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

  test(
    'unified local repository reads canonical store detail surface',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera-comic-detail-repo-',
      );
      final store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
      addTearDown(() async {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await store.init();
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-1',
          title: 'Canonical Local',
          normalizedTitle: 'canonical local',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'comic-1',
          title: 'Canonical Local',
          normalizedTitle: 'canonical local',
          titleType: 'primary',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-1',
          comicId: 'comic-1',
          storageType: 'user_imported',
          localRootPath: '/tmp/local-1',
        ),
      );
      await store.upsertChapter(
        const ChapterRecord(
          id: 'chapter-1',
          comicId: 'comic-1',
          chapterNo: 1,
          title: 'Imported',
          normalizedTitle: 'imported',
        ),
      );
      await store.upsertPage(
        const PageRecord(
          id: 'page-1',
          chapterId: 'chapter-1',
          pageIndex: 0,
          localPath: '/tmp/local-1/1.jpg',
        ),
      );
      await store.upsertPageOrder(
        const PageOrderRecord(
          id: 'order-1',
          chapterId: 'chapter-1',
          orderName: 'Source Default',
          normalizedOrderName: 'source default',
          orderType: 'source_default',
          isActive: true,
        ),
      );
      await store.replacePageOrderItems('order-1', const [
        PageOrderItemRecord(
          pageOrderId: 'order-1',
          pageId: 'page-1',
          sortOrder: 0,
        ),
      ]);
      await store.upsertHistoryEvent(
        const HistoryEventRecord(
          id: 'history-1',
          comicId: 'comic-1',
          sourceTypeValue: 0,
          sourceKey: 'local',
          title: 'Canonical Local',
          subtitle: '',
          cover: '',
          eventTime: '2026-04-30T12:00:00.000Z',
          chapterIndex: 1,
          pageIndex: 3,
          readEpisode: '1',
        ),
      );

      final repository = UnifiedLocalComicDetailRepository(store: store);
      final detail = await repository.getComicDetail('comic-1');

      expect(detail, isNotNull);
      expect(detail!.libraryState, LibraryState.localOnly);
      expect(detail.availableActions.canContinueReading, isTrue);
      expect(detail.chapters.single.title, 'Imported');
      expect(detail.chapters.single.lastReadAt, isNotNull);
      expect(detail.updatedAt, isNotNull);
      expect(
        detail.pageOrderSummary.activeOrderType,
        PageOrderKind.sourceDefault,
      );
      expect(detail.pageOrderSummary.totalPageCount, 1);
      expect(detail.availableActions.canManagePageOrder, isTrue);
    },
  );

  test(
    'unified local repository does not match fractional chapter numbers to integer history',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera-comic-detail-repo-',
      );
      final store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
      addTearDown(() async {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await store.init();
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-2',
          title: 'Fractional Chapter',
          normalizedTitle: 'fractional chapter',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'comic-2',
          title: 'Fractional Chapter',
          normalizedTitle: 'fractional chapter',
          titleType: 'primary',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-2',
          comicId: 'comic-2',
          storageType: 'user_imported',
          localRootPath: '/tmp/local-2',
        ),
      );
      await store.upsertChapter(
        const ChapterRecord(
          id: 'chapter-2',
          comicId: 'comic-2',
          chapterNo: 1.5,
          title: 'Chapter 1.5',
          normalizedTitle: 'chapter 1.5',
        ),
      );
      await store.upsertPage(
        const PageRecord(
          id: 'page-2',
          chapterId: 'chapter-2',
          pageIndex: 0,
          localPath: '/tmp/local-2/1.jpg',
        ),
      );
      await store.upsertHistoryEvent(
        const HistoryEventRecord(
          id: 'history-2',
          comicId: 'comic-2',
          sourceTypeValue: 0,
          sourceKey: 'local',
          title: 'Fractional Chapter',
          subtitle: '',
          cover: '',
          eventTime: '2026-04-30T12:00:00.000Z',
          chapterIndex: 1,
          pageIndex: 0,
          readEpisode: '1',
        ),
      );

      final repository = UnifiedLocalComicDetailRepository(store: store);
      final detail = await repository.getComicDetail('comic-2');

      expect(detail, isNotNull);
      expect(detail!.availableActions.canContinueReading, isTrue);
      expect(detail.chapters.single.lastReadAt, isNull);
    },
  );
}
