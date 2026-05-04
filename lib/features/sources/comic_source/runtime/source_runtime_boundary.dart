import 'source_request_context.dart';
import 'source_runtime_codes.dart';
import 'source_runtime_error.dart';
import 'source_runtime_stage.dart';

abstract final class SourceRuntimeBoundary {
  static SourceRequestContext newContext({
    required String sourceKey,
    String? requestId,
    String? accountProfileId,
    int? accountRevision,
    String? headerProfile,
  }) {
    return SourceRequestContext(
      sourceKey: sourceKey,
      requestId:
          requestId ??
          'src-$sourceKey-${DateTime.now().microsecondsSinceEpoch}',
      createdAt: DateTime.now(),
      accountProfileId: accountProfileId,
      accountRevision: accountRevision,
      headerProfile: headerProfile,
    );
  }

  static SourceRuntimeError invalidSettingsShape({
    required SourceRequestContext context,
    required Object rawValue,
  }) {
    return SourceRuntimeError(
      code: SourceRuntimeCodes.settingsInvalid,
      message: 'Invalid dynamic settings shape.',
      diagnosticMessage: 'Expected map, got ${rawValue.runtimeType}.',
      sourceKey: context.sourceKey,
      requestId: context.requestId,
      accountProfileId: context.accountProfileId,
      stage: SourceRuntimeStage.parser,
      cause: rawValue,
    );
  }
}
