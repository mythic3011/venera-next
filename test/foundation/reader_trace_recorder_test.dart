import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/reader/reader_trace_recorder.dart';

void main() {
  test('ring_buffer_keeps_latest_100_events', () {
    final recorder = ReaderTraceRecorder(maxEvents: 100);
    for (var i = 0; i < 105; i++) {
      recorder.record(
        ReaderTraceEvent(
          event: 'event-$i',
          timestamp: DateTime.utc(2026, 1, 1),
          phase: ReaderTracePhase.pageList,
        ),
      );
    }

    final json = recorder.toDiagnosticsJson();
    final trace = json['readerTrace'] as Map<String, dynamic>;
    final events = trace['events'] as List<dynamic>;
    expect(trace['eventCount'], 100);
    expect(events.first['event'], 'event-5');
    expect(events.last['event'], 'event-104');
  });

  test('long_strings_are_capped_and_url_query_fragment_stripped', () {
    final recorder = ReaderTraceRecorder();
    final long = 'x' * 200;
    recorder.record(
      ReaderTraceEvent(
        event: long,
        timestamp: DateTime.utc(2026, 1, 1),
        imageKey:
            'https://example.com/image/path/asset.webp?token=abc123#fragment',
        thumbnailUrl:
            'https://example.com/thumb.png?session=secret#hash-fragment',
        sourceUrl: 'https://example.com/source?id=1&account=demo#state',
        phase: ReaderTracePhase.thumbnail,
      ),
    );

    final json = recorder.toDiagnosticsJson();
    final event =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;

    expect((event['event'] as String).length, 160);
    expect(event['imageKey'], 'https://example.com/image/path/asset.webp');
    expect(event['thumbnailUrl'], 'https://example.com/thumb.png');
    expect(event['sourceUrl'], 'https://example.com/source');
  });

  test('secret_like_text_is_redacted', () {
    final recorder = ReaderTraceRecorder();
    recorder.record(
      ReaderTraceEvent(
        event: 'pageList.load.error',
        timestamp: DateTime.utc(2026, 1, 1),
        errorMessage: 'authorization=Bearer123 token=abc password=secret',
        phase: ReaderTracePhase.pageList,
      ),
    );

    final json = recorder.toDiagnosticsJson();
    final event =
        (json['readerTrace'] as Map<String, dynamic>)['events'][0]
            as Map<String, dynamic>;
    final errorMessage = event['errorMessage'] as String;
    expect(errorMessage.contains('authorization=<redacted>'), isTrue);
    expect(errorMessage.contains('token=<redacted>'), isTrue);
    expect(errorMessage.contains('password=<redacted>'), isTrue);
  });

  test('to_diagnostics_json_shape_matches_contract', () {
    final recorder = ReaderTraceRecorder();
    final json = recorder.toDiagnosticsJson();
    expect(json.keys, ['readerTrace']);
    final trace = json['readerTrace'] as Map<String, dynamic>;
    expect(trace['maxEvents'], 100);
    expect(trace['eventCount'], 0);
    expect(trace['events'], isA<List<dynamic>>());
  });
}
