import 'source_request_context.dart';
import 'source_runtime_error.dart';

abstract interface class SourceRequestPolicy {
  SourceRuntimeError? classifyException({
    required Object error,
    required SourceRequestContext context,
    StackTrace? stackTrace,
  });
}
