import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/features/reader_next/runtime/models.dart'
    as runtime_models;
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/history_page.dart';

void main() {
  runtime_models.ReaderNextOpenRequest sampleRequest() {
    return runtime_models.ReaderNextOpenRequest.remote(
      canonicalComicId: runtime_models.CanonicalComicId.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
      ),
      sourceRef: runtime_models.SourceRef.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
        chapterRefId: '1',
      ),
      initialPage: 1,
    );
  }

  testWidgets(
    'HistoryPage uses approved default ReaderNext executor when none injected',
    (tester) async {
      var approvedFactoryCalls = 0;
      var approvedExecutorCalls = 0;
      final request = sampleRequest();

      final executor = resolveHistoryReaderNextExecutor(
        approvedFactory: () {
          approvedFactoryCalls += 1;
          return (runtime_models.ReaderNextOpenRequest req) async {
            approvedExecutorCalls += 1;
            expect(identical(req, request), isTrue);
          };
        },
      );
      await executor(request);

      expect(approvedFactoryCalls, 1);
      expect(approvedExecutorCalls, 1);
    },
  );

  testWidgets('HistoryPage injected executor overrides default executor', (
    tester,
  ) async {
    var defaultFactoryCalls = 0;
    var fakeExecutorCalls = 0;
    final request = sampleRequest();

    Future<void> fakeExecutor(runtime_models.ReaderNextOpenRequest req) async {
      fakeExecutorCalls += 1;
      expect(identical(req, request), isTrue);
    }

    final resolved = resolveHistoryReaderNextExecutor(
      injectedExecutor: fakeExecutor,
      approvedFactory: () {
        defaultFactoryCalls += 1;
        return (_) async {};
      },
    );

    await resolved(request);
    expect(fakeExecutorCalls, 1);
    expect(defaultFactoryCalls, 0);
  });

  testWidgets(
    'history activity local tap opens detail route instead of ReaderWithLoading',
    (tester) async {
      final item = ReaderActivityItem(
        comicId: 'comic-local',
        title: 'Local Comic',
        subtitle: '',
        cover: 'file:///tmp/local-cover.png',
        sourceKey: 'local',
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-local',
          chapterId: '1:__imported__',
        ),
        chapterId: '1:__imported__',
        pageIndex: 4,
        lastReadAt: DateTime.utc(2026, 5, 3),
      );

      final page = buildHistoryComicDetailRouteForTesting(item);

      expect(page, isA<ComicDetailPage>());
      final detail = page as ComicDetailPage;
      expect(detail.comicId, 'comic-local');
      expect(detail.progressContext?.chapterId, '1:__imported__');
      expect(detail.progressContext?.page, 4);
    },
  );

  testWidgets('history detail route carries progress fallback context', (
    tester,
  ) async {
    final item = ReaderActivityItem(
      comicId: 'comic-local',
      title: 'Local Comic',
      subtitle: '',
      cover: 'file:///tmp/local-cover.png',
      sourceKey: 'local',
      sourceRef: SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-local',
        chapterId: '2:__imported__',
      ),
      chapterId: '2:__imported__',
      pageIndex: 9,
      lastReadAt: DateTime.utc(2026, 5, 3),
    );

    final progress = buildHistoryDetailProgressContextForTesting(item);

    expect(progress.chapterId, '2:__imported__');
    expect(progress.page, 9);
    expect(progress.sourceRef?.id, item.sourceRef.id);
  });

  testWidgets('remote history activity still opens remote detail route', (
    tester,
  ) async {
    final item = ReaderActivityItem(
      comicId: '646922',
      title: 'Remote Comic',
      subtitle: '',
      cover: 'https://example.com/cover.jpg',
      sourceKey: 'nhentai',
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: 'nhentai',
        comicId: '646922',
        chapterId: '1',
      ),
      chapterId: '1',
      pageIndex: 2,
      lastReadAt: DateTime.utc(2026, 5, 3),
    );

    final page = buildHistoryComicDetailRouteForTesting(item);

    expect(page, isA<ComicPage>());
    final detail = page as ComicPage;
    expect(detail.sourceKey, 'nhentai');
    expect(detail.id, '646922');
    expect(detail.progressContext?.chapterId, '1');
    expect(detail.progressContext?.page, 2);
  });
}
