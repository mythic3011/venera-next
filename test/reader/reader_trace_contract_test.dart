import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/foundation/reader/reader_trace_recorder.dart';
import 'package:venera/pages/reader/reader.dart';

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
}
