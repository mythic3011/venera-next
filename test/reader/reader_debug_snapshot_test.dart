import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/foundation/reader/reader_debug_snapshot.dart';
import 'package:venera/foundation/reader/reader_trace_recorder.dart';

void main() {
  late Directory tempDir;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'venera-reader-debug-snapshot-test-',
    );
    store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    await store.init();
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() async {
    AppDiagnostics.resetForTesting();
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('snapshot exposes canonical local reader identifiers', () async {
    await _insertCanonicalReaderFixture(store);

    final snapshot =
        await ReaderDebugSnapshotService(
          localLibraryStore: store,
          comicDetailStore: store,
        ).build(
          comicId: 'comic-1',
          chapterId: 'chapter-1',
          loadMode: 'local',
          controllerLifecycle: 'open',
        );

    expect(snapshot.comicId, 'comic-1');
    expect(snapshot.localLibraryItemId, 'local_item:comic-1');
    expect(snapshot.pageOrderId, 'order-1');
    expect(snapshot.chapterId, 'chapter-1');
    expect(snapshot.sourcePlatformId, 'platform-1');
    expect(snapshot.sourceComicId, 'source-comic-1');
    expect(snapshot.linkStatus, 'active');
    expect(snapshot.loadMode, 'local');
    expect(snapshot.controllerLifecycle, 'open');
    expect(snapshot.toJson()['comicId'], 'comic-1');
    expect(snapshot.toJson()['sourcePlatformId'], 'platform-1');
    expect(snapshot.toJson()['sourceComicId'], 'source-comic-1');
    expect(snapshot.toJson()['linkStatus'], 'active');
  });

  test('snapshot fails loudly when canonical comic is missing', () async {
    await expectLater(
      ReaderDebugSnapshotService(
        localLibraryStore: store,
        comicDetailStore: store,
      ).build(
        comicId: 'missing',
        chapterId: 'chapter-1',
        loadMode: 'local',
        controllerLifecycle: 'open',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('snapshot fails loudly when active page order is missing', () async {
    await _insertCanonicalReaderFixture(store, includePageOrder: false);

    await expectLater(
      ReaderDebugSnapshotService(
        localLibraryStore: store,
        comicDetailStore: store,
      ).build(
        comicId: 'comic-1',
        chapterId: 'chapter-1',
        loadMode: 'local',
        controllerLifecycle: 'open',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'reader diagnostics emits stable correlation id across call timeline',
    () {
      readerTraceRecorder.clear();
      final callId = ReaderDiagnostics.beginImageLoad(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-1',
        chapterId: 'chapter-1',
        page: 2,
        imageKey: 'file:///tmp/page-2.jpg',
      );
      ReaderDiagnostics.endImageLoad(
        callId: callId,
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-1',
        chapterId: 'chapter-1',
        page: 2,
        imageKey: 'file:///tmp/page-2.jpg',
        byteLength: 42,
      );

      final events =
          (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                  as Map<String, dynamic>)['events']
              as List<dynamic>;
      final start = events.first as Map<String, dynamic>;
      final end = events.last as Map<String, dynamic>;
      expect(start['callId'], callId);
      expect(end['callId'], callId);

      final readerLoadEvents = DevDiagnosticsApi.recent(channel: 'reader.load');
      final startEvent = readerLoadEvents.firstWhere(
        (event) => event.message == 'call.start',
      );
      final endEvent = readerLoadEvents.firstWhere(
        (event) => event.message == 'call.end',
      );
      final startCorrelationId = startEvent.data['correlationId']?.toString();
      final endCorrelationId = endEvent.data['correlationId']?.toString();
      expect(startCorrelationId, isNotNull);
      expect(startCorrelationId, isNotEmpty);
      expect(startCorrelationId, endCorrelationId);
      expect(startCorrelationId, contains('ReaderImageProvider.load'));
    },
  );
}

Future<void> _insertCanonicalReaderFixture(
  UnifiedComicsStore store, {
  bool includePageOrder = true,
}) async {
  await store.upsertComic(
    const ComicRecord(
      id: 'comic-1',
      title: 'Comic One',
      normalizedTitle: 'comic one',
    ),
  );
  await store.upsertLocalLibraryItem(
    const LocalLibraryItemRecord(
      id: 'local_item:comic-1',
      comicId: 'comic-1',
      storageType: 'user_imported',
      localRootPath: '/library/comic-1',
    ),
  );
  await store.upsertSourcePlatform(
    const SourcePlatformRecord(
      id: 'platform-1',
      canonicalKey: 'platform-1',
      displayName: 'Platform 1',
      kind: 'remote',
    ),
  );
  await store.upsertComicSourceLink(
    const ComicSourceLinkRecord(
      id: 'link-1',
      comicId: 'comic-1',
      sourcePlatformId: 'platform-1',
      sourceComicId: 'source-comic-1',
      linkStatus: 'active',
      isPrimary: true,
    ),
  );
  await store.upsertChapter(
    const ChapterRecord(
      id: 'chapter-1',
      comicId: 'comic-1',
      chapterNo: 1,
      title: 'Chapter 1',
      normalizedTitle: 'chapter 1',
    ),
  );
  await store.upsertPage(
    const PageRecord(
      id: 'page-1',
      chapterId: 'chapter-1',
      pageIndex: 0,
      localPath: '/library/comic-1/1.png',
    ),
  );
  if (!includePageOrder) {
    return;
  }
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
    PageOrderItemRecord(pageOrderId: 'order-1', pageId: 'page-1', sortOrder: 0),
  ]);
}
