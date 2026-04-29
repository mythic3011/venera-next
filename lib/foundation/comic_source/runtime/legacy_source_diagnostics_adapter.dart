import 'package:venera/foundation/diagnostics/diagnostics.dart';

import 'source_request_context.dart';
import 'source_runtime_codes.dart';
import 'source_runtime_error.dart';
import 'source_runtime_stage.dart';

abstract final class LegacySourceDiagnosticsAdapter {
  static SourceRuntimeError mapException({
    required Object error,
    required SourceRequestContext context,
    StackTrace? stackTrace,
  }) {
    final normalized = error.toString().toLowerCase();

    if (_looksLikeTimeout(normalized)) {
      return _record(
        SourceRuntimeError(
          code: SourceRuntimeCodes.requestTimeout,
          message: 'Legacy request timed out.',
          sourceKey: context.sourceKey,
          requestId: context.requestId,
          accountProfileId: context.accountProfileId,
          stage: SourceRuntimeStage.request,
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
          stage: SourceRuntimeStage.parser,
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
        stage: SourceRuntimeStage.legacy,
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
}
