import 'source_runtime_error.dart';

sealed class SourceRuntimeResult<T> {
  const SourceRuntimeResult();
}

class SourceRuntimeSuccess<T> extends SourceRuntimeResult<T> {
  const SourceRuntimeSuccess(this.value);

  final T value;
}

class SourceRuntimeFailure<T> extends SourceRuntimeResult<T> {
  const SourceRuntimeFailure(this.error);

  final SourceRuntimeError error;
}
