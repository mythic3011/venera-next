import 'source_runtime_stage.dart';
import 'source_runtime_codes.dart';

class SourceRuntimeError implements Exception {
  final String code;
  final String message;
  final String? diagnosticMessage;
  final String sourceKey;
  final String? requestId;
  final String? accountProfileId;
  final SourceRuntimeStage stage;
  final Object? cause;

  const SourceRuntimeError({
    required this.code,
    required this.message,
    required this.sourceKey,
    required this.stage,
    this.diagnosticMessage,
    this.requestId,
    this.accountProfileId,
    this.cause,
  });

  String get userMessage => message;

  String get sourceMeaningCode => SourceRuntimeCodes.toSourceMeaning(code);

  String toUiMessage() => '$sourceMeaningCode:$userMessage';

  Map<String, Object?> toDiagnosticJson() => {
    'code': code,
    'sourceMeaningCode': sourceMeaningCode,
    'message': message,
    if (diagnosticMessage != null) 'diagnosticMessage': diagnosticMessage,
    'sourceKey': sourceKey,
    'stage': stage.name,
    if (requestId != null) 'requestId': requestId,
  };

  @override
  String toString() {
    final requestPart = requestId == null ? '' : ', requestId: $requestId';
    return 'SourceRuntimeError(code: $code, message: $message, sourceKey: $sourceKey, stage: ${stage.name}$requestPart)';
  }
}
