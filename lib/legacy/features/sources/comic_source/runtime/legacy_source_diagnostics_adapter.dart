import 'package:venera/foundation/diagnostics/diagnostics.dart';

import 'source_request_context.dart';
import 'source_runtime_codes.dart';
import 'source_runtime_error.dart';
import 'source_runtime_stage.dart';

abstract final class LegacySourceDiagnosticsAdapter {
  static SourceRuntimeError mapException({
    required Object error,
    required SourceRequestContext context,
    SourceRuntimeStage? stageOverride,
    String? codeOverride,
    String? messageOverride,
    StackTrace? stackTrace,
  }) {
    final normalized = error.toString().toLowerCase();

    if (codeOverride != null || messageOverride != null) {
      return _record(
        SourceRuntimeError(
          code: codeOverride ?? SourceRuntimeCodes.legacyUnknown,
          message: messageOverride ?? 'Legacy source runtime failure.',
          sourceKey: context.sourceKey,
          requestId: context.requestId,
          accountProfileId: context.accountProfileId,
          stage: stageOverride ?? SourceRuntimeStage.legacy,
          cause: error,
        ),
      );
    }

    if (_looksLikeTimeout(normalized)) {
      return _record(
        SourceRuntimeError(
          code: SourceRuntimeCodes.requestTimeout,
          message: 'Legacy request timed out.',
          sourceKey: context.sourceKey,
          requestId: context.requestId,
          accountProfileId: context.accountProfileId,
          stage: stageOverride ?? SourceRuntimeStage.request,
          cause: error,
        ),
      );
    }

    if (_looksLikeParserError(normalized)) {
      return _record(
        SourceRuntimeError(
          code: SourceRuntimeCodes.parserInvalidContent,
          message: 'Legacy parser/content handling failed.',
          sourceKey: context.sourceKey,
          requestId: context.requestId,
          accountProfileId: context.accountProfileId,
          stage: stageOverride ?? SourceRuntimeStage.parser,
          cause: error,
        ),
      );
    }

    if (_looksLikeJsRuntimeError(normalized)) {
      return _record(
        SourceRuntimeError(
          code: SourceRuntimeCodes.legacyUnknown,
          message: 'Legacy JavaScript runtime failure.',
          sourceKey: context.sourceKey,
          requestId: context.requestId,
          accountProfileId: context.accountProfileId,
          stage: stageOverride ?? SourceRuntimeStage.legacy,
          cause: error,
        ),
      );
    }

    return _record(
      SourceRuntimeError(
        code: SourceRuntimeCodes.legacyUnknown,
        message: 'Legacy source runtime failure.',
        sourceKey: context.sourceKey,
        requestId: context.requestId,
        accountProfileId: context.accountProfileId,
        stage: stageOverride ?? SourceRuntimeStage.legacy,
        cause: error,
      ),
    );
  }

  static SourceRuntimeError _record(SourceRuntimeError error) {
    AppDiagnostics.warn(
      'source.runtime',
      error.message,
      data: {
        'sourceKey': error.sourceKey,
        'requestId': error.requestId,
        'stage': error.stage.name,
        'errorCode': error.code,
      },
    );
    return error;
  }

  static bool _looksLikeTimeout(String value) =>
      value.contains('timeout') || value.contains('timed out');

  static bool _looksLikeParserError(String value) =>
      value.contains('parse') ||
      value.contains('parser') ||
      value.contains('invalid content') ||
      value.contains('unexpected content') ||
      value.contains('malformed');

  static bool _looksLikeJsRuntimeError(String value) =>
      value.contains('referenceerror') || value.contains('typeerror');
}
