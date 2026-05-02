import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/foundation/reader/reader_trace_recorder.dart';
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/features/reader/presentation/reader.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test('required_event_name_and_phase_serialize_consistently', () {
    final recorder = ReaderTraceRecorder();
    recorder.record(
      ReaderTraceEvent(
        event: 'pageList.load.start',
        timestamp: DateTime.utc(2026, 1, 1),
        loadMode: 'remote',
        sourceKey: 'copymanga',
        comicId: 'comic-1',
        chapterId: 'ch-1',
        chapterIndex: 3,
        page: 7,
        phase: ReaderTracePhase.pageList,
      ),
    );

    final json = recorder.toDiagnosticsJson();
    final event =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;
    expect(event['event'], 'pageList.load.start');
    expect(event['phase'], 'pageList');
    expect(event['loadMode'], 'remote');
    expect(event['sourceKey'], 'copymanga');
    expect(event['comicId'], 'comic-1');
    expect(event['chapterId'], 'ch-1');
    expect(event['chapterIndex'], 3);
    expect(event['page'], 7);
  });

  test('all_phases_serialize_to_stable_names', () {
    expect(ReaderTracePhase.sourceResolution.name, 'sourceResolution');
    expect(ReaderTracePhase.pageList.name, 'pageList');
    expect(ReaderTracePhase.thumbnail.name, 'thumbnail');
    expect(ReaderTracePhase.imageProvider.name, 'imageProvider');
    expect(ReaderTracePhase.decode.name, 'decode');
    expect(ReaderTracePhase.cache.name, 'cache');
  });

  test('reader dispose trace keeps expected diagnostic fields', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: ComicType.local,
      comicId: 'comic-7',
      chapterId: 'ch-3',
      chapterIndex: 3,
      page: 9,
    );

    final json = ReaderDiagnostics.toDiagnosticsJson();
    final recordedEvent =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;

    expect(recordedEvent['event'], 'reader.dispose');
    expect(recordedEvent['phase'], 'sourceResolution');
    expect(recordedEvent['loadMode'], 'local');
    expect(recordedEvent['sourceKey'], 'local');
    expect(recordedEvent['comicId'], 'comic-7');
    expect(recordedEvent['chapterId'], 'ch-3');
    expect(recordedEvent['chapterIndex'], 3);
    expect(recordedEvent['page'], 9);
  });

  test('reader lifecycle also emits structured diagnostic event', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.open',
      type: ComicType.local,
      comicId: 'comic-7',
      chapterId: 'ch-3',
      chapterIndex: 3,
      page: 9,
    );

    final event = DevDiagnosticsApi.recent(channel: 'reader.lifecycle').single;
    expect(event.message, 'reader.open');
    expect(event.data['sourceKey'], 'local');
    expect(event.data['comicId'], 'comic-7');
    expect(event.data['chapterId'], 'ch-3');
    expect(event.data['page'], 9);
  });

  test('reader dispose lifecycle carries cause tab and duration metadata', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordReaderLifecycle(
      event: 'reader.dispose',
      type: ComicType.local,
      comicId: 'comic-7',
      chapterId: 'ch-3',
      chapterIndex: 3,
      page: 9,
      resultSummary:
          'cause=State.dispose owner=Reader.dispose expectedReaderTabId=tab-7 openDurationMs=2700',
      data: const {
        'disposeCause': 'State.dispose',
        'disposeOwner': 'Reader.dispose',
        'expectedReaderTabId': 'tab-7',
        'openDurationMs': 2700,
      },
    );

    final json = ReaderDiagnostics.toDiagnosticsJson();
    final recordedEvent =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;
    final diagnosticEvent = DevDiagnosticsApi.recent(
      channel: 'reader.lifecycle',
    ).single;

    expect(recordedEvent['event'], 'reader.dispose');
    expect(recordedEvent['resultSummary'], contains('openDurationMs=2700'));
    expect(diagnosticEvent.data['disposeCause'], 'State.dispose');
    expect(diagnosticEvent.data['disposeOwner'], 'Reader.dispose');
    expect(diagnosticEvent.data['expectedReaderTabId'], 'tab-7');
    expect(diagnosticEvent.data['openDurationMs'], 2700);
  });

  test('local reader tab remains active after page list load success', () {
    final data = buildReaderTabRetentionDiagnosticForTesting(
      expectedReaderTabId: 'local:local:1:1:__imported__',
      activeReaderTabId: 'local:local:1:1:__imported__',
      pageOrderId: '1:__imported__:source_default',
      comicId: '1',
      loadMode: 'local',
      sourceKey: 'local',
      chapterId: '1:__imported__',
      chapterIndex: 1,
      page: 1,
    );

    expect(data['retained'], isTrue);
    expect(data['status'], 'active');
    expect(data['activeReaderTabId'], data['expectedReaderTabId']);
    expect(data['pageOrderId'], '1:__imported__:source_default');
  });

  test('dispose diagnostics can skip layout dependent pagination reads', () {
    final snapshot = buildReaderPaginationDiagnosticsForTesting(
      includePagination: false,
      imageCount: 3,
      maxPage: () => throw StateError('maxPage should not be read'),
      imagesPerPage: () => throw StateError('imagesPerPage should not be read'),
    );

    expect(snapshot.maxPage, isNull);
    expect(snapshot.imagesPerPage, isNull);
  });

  test('pagination diagnostics degrade when layout reads fail', () {
    final snapshot = buildReaderPaginationDiagnosticsForTesting(
      includePagination: true,
      imageCount: 3,
      maxPage: () => throw StateError('layout unavailable'),
      imagesPerPage: () => throw StateError('layout unavailable'),
    );

    expect(snapshot.imageCount, 3);
    expect(snapshot.maxPage, isNull);
    expect(snapshot.imagesPerPage, isNull);
    final diagnosticEvent = DevDiagnosticsApi.recent(
      channel: 'reader.lifecycle',
    ).single;
    expect(diagnosticEvent.message, 'pagination.diagnostics.unavailable');
    expect(diagnosticEvent.data['reason'], 'pagination_snapshot_unavailable');
    expect(diagnosticEvent.data.containsKey('stackTrace'), isFalse);
  });

  test(
    'dispose diagnostics use context unavailable reason without stack spam',
    () {
      buildReaderPaginationDiagnosticsForTesting(
        includePagination: true,
        imageCount: 3,
        maxPage: () => throw StateError('layout unavailable during dispose'),
        imagesPerPage: () =>
            throw StateError('layout unavailable during dispose'),
        unavailableReason: 'context_unavailable_during_dispose',
      );

      final diagnosticEvent = DevDiagnosticsApi.recent(
        channel: 'reader.lifecycle',
      ).single;
      expect(diagnosticEvent.message, 'pagination.diagnostics.unavailable');
      expect(
        diagnosticEvent.data['reason'],
        'context_unavailable_during_dispose',
      );
      expect(diagnosticEvent.data.containsKey('stackTrace'), isFalse);
    },
  );

  test(
    'reader image load calls keep source comic chapter and page context',
    () {
      readerTraceRecorder.clear();
      final callId = ReaderDiagnostics.beginImageLoad(
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
      );
      ReaderDiagnostics.endImageLoad(
        callId: callId,
        loadMode: 'local',
        sourceKey: 'local',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
        imageKey: 'file:///tmp/page-4.jpg',
        byteLength: 1234,
      );

      final json = ReaderDiagnostics.toDiagnosticsJson();
      final events =
          (json['readerTrace'] as Map<String, dynamic>)['events']
              as List<dynamic>;
      final start = events.first as Map<String, dynamic>;
      final end = events.last as Map<String, dynamic>;

      expect(start['functionName'], 'ReaderImageProvider.load');
      expect(start['phase'], 'imageProvider');
      expect(start['sourceKey'], 'local');
      expect(start['comicId'], 'comic-7');
      expect(start['chapterId'], 'ch-3');
      expect(start['page'], 4);
      expect(end['resultSummary'], 'bytes=1234');
    },
  );

  test(
    'reader image decode errors keep source comic chapter and page context',
    () {
      readerTraceRecorder.clear();
      ReaderDiagnostics.recordImageLoadError(
        error: 'decode failed',
        imageKey: 'https://example.com/page-4.jpg',
        sourceKey: 'copymanga',
        comicId: 'comic-7',
        chapterId: 'ch-3',
        page: 4,
      );

      final json = ReaderDiagnostics.toDiagnosticsJson();
      final recordedEvent =
          (json['readerTrace'] as Map<String, dynamic>)['events'][0]
              as Map<String, dynamic>;
      final diagnosticEvent = DevDiagnosticsApi.recent(
        channel: 'reader.decode',
      ).single;

      expect(recordedEvent['sourceKey'], 'copymanga');
      expect(recordedEvent['comicId'], 'comic-7');
      expect(recordedEvent['chapterId'], 'ch-3');
      expect(recordedEvent['page'], 4);
      expect(recordedEvent['imageKey'], 'https://example.com/page-4.jpg');
      expect(diagnosticEvent.data['sourceKey'], 'copymanga');
      expect(diagnosticEvent.data['comicId'], 'comic-7');
      expect(diagnosticEvent.data['chapterId'], 'ch-3');
      expect(diagnosticEvent.data['page'], 4);
    },
  );

  test('reader decode success/error and frame events are distinguishable', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordImageDecodeSuccess(
      imageKey: 'https://example.com/page-5.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-7',
      chapterId: 'ch-3',
      page: 5,
      byteLength: 2048,
    );
    ReaderDiagnostics.recordImageDecodeError(
      imageKey: 'https://example.com/page-6.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-7',
      chapterId: 'ch-3',
      page: 6,
      error: 'bad codec',
    );
    ReaderDiagnostics.recordImageFrameRendered(
      imageKey: 'https://example.com/page-5.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-7',
      chapterId: 'ch-3',
      page: 5,
      frameNumber: 0,
      synchronousCall: false,
      widgetType: 'ComicImage',
    );

    final events =
        (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                as Map<String, dynamic>)['events']
            as List<dynamic>;
    expect(events[0]['event'], 'image.decode.success');
    expect(events[1]['event'], 'image.decode.error');
    expect(events[2]['event'], 'image.frame.rendered');
    expect(events[0]['phase'], 'decode');
    expect(events[1]['phase'], 'decode');
    expect(events[2]['phase'], 'decode');

    final decodeEvents = DevDiagnosticsApi.recent(channel: 'reader.decode');
    expect(decodeEvents.map((e) => e.message), [
      'image.decode.success',
      'bad codec',
      'image.frame.rendered',
    ]);
  });

  test('canonical session events serialize as structured diagnostics', () {
    readerTraceRecorder.clear();
    ReaderDiagnostics.recordCanonicalSessionEvent(
      event: 'reader.session.upsert.success',
      loadMode: 'local',
      sourceKey: 'local',
      comicId: 'comic-9',
      chapterId: '0',
      chapterIndex: 1,
      page: 6,
      sessionId: 'reader-session:comic-9',
      tabId: 'local:local:comic-9:_',
    );

    final traceEvent =
        (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;
    final structured = DevDiagnosticsApi.recent(
      channel: 'reader.session',
    ).single;

    expect(traceEvent['event'], 'reader.session.upsert.success');
    expect(traceEvent['sourceKey'], 'local');
    expect(traceEvent['chapterId'], '0');
    expect(traceEvent['resultSummary'], contains('sessionId='));
    expect(structured.data['sessionId'], isNotNull);
    expect(structured.data['tabId'], isNotNull);
  });

  test(
    'normalized reader context stays stable across page list image provider and dispose',
    () {
      readerTraceRecorder.clear();
      final context = buildReaderRuntimeContextForTesting(
        comicId: 'comic-10',
        type: ComicType.local,
        chapterIndex: 1,
        page: 3,
        chapterId: null,
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-10',
          chapterId: null,
        ),
      );

      ReaderDiagnostics.beginPageListLoad(
        loadMode: context.loadMode,
        sourceKey: context.sourceKey,
        comicId: context.comicId,
        chapterId: context.chapterId,
        chapterIndex: context.chapterIndex,
        page: context.page,
      );
      ReaderDiagnostics.recordImageProviderCreated(
        type: ComicType.local,
        comicId: context.comicId,
        chapterId: context.chapterId,
        chapterIndex: context.chapterIndex,
        page: context.page,
        imageKey: 'file:///tmp/page-3.jpg',
      );
      ReaderDiagnostics.recordReaderLifecycle(
        event: 'reader.dispose',
        type: ComicType.local,
        comicId: context.comicId,
        chapterId: context.chapterId,
        chapterIndex: context.chapterIndex,
        page: context.page,
        sourceKey: context.sourceKey,
        loadMode: context.loadMode,
      );

      final events =
          (ReaderDiagnostics.toDiagnosticsJson()['readerTrace']
                  as Map<String, dynamic>)['events']
              as List<dynamic>;

      expect(
        events.every(
          (event) => (event as Map<String, dynamic>)['sourceKey'] == 'local',
        ),
        isTrue,
      );
      expect(
        events.every(
          (event) => (event as Map<String, dynamic>)['chapterId'] == '0',
        ),
        isTrue,
      );
      expect(normalizeReaderChapterIdForTesting(null), '0');
    },
  );
}
