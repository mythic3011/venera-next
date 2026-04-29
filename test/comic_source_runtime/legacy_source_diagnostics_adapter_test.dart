import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/runtime.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  SourceRequestContext context() => SourceRequestContext(
    sourceKey: 'copymanga',
    requestId: 'req-1',
    createdAt: DateTime.utc(2026, 4, 28, 15, 0, 0),
    accountProfileId: 'account-1',
    accountRevision: 1,
    headerProfile: 'stable',
  );

  test('legacy_adapter_maps_timeout_error_to_request_timeout', () {
    final mapped = LegacySourceDiagnosticsAdapter.mapException(
      error: Exception('Request timed out after 10 seconds'),
      context: context(),
    );

    expect(mapped.code, SourceRuntimeCodes.requestTimeout);
  });

  test('legacy_adapter_emits_source_runtime_diagnostic', () {
    LegacySourceDiagnosticsAdapter.mapException(
      error: FormatException('Parser failed: token=secret'),
      context: context(),
    );

    final event = DevDiagnosticsApi.recent(channel: 'source.runtime').single;
    expect(event.level, DiagnosticLevel.warn);
    expect(event.data['sourceKey'], 'copymanga');
    expect(event.data['requestId'], 'req-1');
    expect(event.data['stage'], 'parser');
    expect(event.data['errorCode'], SourceRuntimeCodes.parserInvalidContent);
    expect(event.toJson().toString().contains('secret'), isFalse);
  });

  test('legacy_adapter_maps_parser_like_error_to_parser_invalid_content', () {
    final mapped = LegacySourceDiagnosticsAdapter.mapException(
      error: FormatException('Parser failed: invalid content at token 4'),
      context: context(),
    );

    expect(mapped.code, SourceRuntimeCodes.parserInvalidContent);
  });

  test('legacy_adapter_maps_unknown_error_to_legacy_unknown', () {
    final mapped = LegacySourceDiagnosticsAdapter.mapException(
      error: StateError('unexpected unknown condition'),
      context: context(),
    );

    expect(mapped.code, SourceRuntimeCodes.legacyUnknown);
  });

  test('legacy_adapter_defaults_stage_to_legacy_for_unknown_mapping', () {
    final mapped = LegacySourceDiagnosticsAdapter.mapException(
      error: StateError('unexpected unknown condition'),
      context: context(),
    );

    expect(mapped.stage, SourceRuntimeStage.legacy);
  });

  test('legacy_adapter_does_not_throw_for_non_exception_object', () {
    expect(
      () => LegacySourceDiagnosticsAdapter.mapException(
        error: 12345,
        context: context(),
      ),
      returnsNormally,
    );
  });
}
