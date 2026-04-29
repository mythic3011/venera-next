import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

void main() {
  tearDown(() {
    DevDiagnosticsApi.debugEnabledOverride = null;
    AppDiagnostics.resetForTesting();
  });

  test('diagnosticsEnabled follows debug or environment flag', () {
    expect(diagnosticsEnabled(isDebugMode: false, envEnabled: false), isFalse);
    expect(diagnosticsEnabled(isDebugMode: true, envEnabled: false), isTrue);
    expect(diagnosticsEnabled(isDebugMode: false, envEnabled: true), isTrue);
    expect(diagnosticsEnabled(isDebugMode: true, envEnabled: true), isTrue);
  });

  test('redaction removes secret-like fields and url query strings', () {
    final redacted = DiagnosticsRedactor.redact({
      'token': 'abc',
      'nested': {
        'Authorization': 'Bearer secret',
        'url': 'https://example.test/path?account=abc&x=1',
      },
      'items': ['password=secret', 'Cookie: session=abc'],
    });

    final text = redacted.toString();
    expect(text.contains('abc'), isFalse);
    expect(text.contains('secret'), isFalse);
    expect(text.contains('?account='), isFalse);
    expect(text.contains('[redacted]'), isTrue);
  });

  test('level filtering returns expected min-level events', () {
    AppDiagnostics.configureSinksForTesting(const []);
    AppDiagnostics.trace('test.trace', 'a');
    AppDiagnostics.info('test.info', 'b');
    AppDiagnostics.warn('test.warn', 'c');
    AppDiagnostics.error('test.error', StateError('d'));

    final warnOrHigher = DevDiagnosticsApi.recent(
      minLevel: DiagnosticLevel.warn,
    );

    expect(warnOrHigher.map((event) => event.level), [
      DiagnosticLevel.warn,
      DiagnosticLevel.error,
    ]);
  });

  test('ring buffer evicts oldest events', () {
    final buffer = DiagnosticRingBuffer(maxEvents: 2);
    buffer.record(
      DiagnosticEvent(
        timestamp: DateTime(2026),
        level: DiagnosticLevel.info,
        channel: 'test',
        message: 'first',
      ),
    );
    buffer.record(
      DiagnosticEvent(
        timestamp: DateTime(2026),
        level: DiagnosticLevel.info,
        channel: 'test',
        message: 'second',
      ),
    );
    buffer.record(
      DiagnosticEvent(
        timestamp: DateTime(2026),
        level: DiagnosticLevel.info,
        channel: 'test',
        message: 'third',
      ),
    );

    expect(buffer.recent().map((event) => event.message), ['second', 'third']);
  });

  test('AppDiagnostics.error captures errorType and stack trace', () {
    AppDiagnostics.configureSinksForTesting(const []);
    AppDiagnostics.error(
      'test.error',
      StateError('bad token=abc'),
      stackTrace: StackTrace.fromString('frame password=secret'),
    );

    final event = DevDiagnosticsApi.recent().single;
    expect(event.level, DiagnosticLevel.error);
    expect(event.errorType, 'StateError');
    expect(event.message.contains('token=abc'), isFalse);
    expect(event.stackTrace!.contains('password=secret'), isFalse);
  });
}
