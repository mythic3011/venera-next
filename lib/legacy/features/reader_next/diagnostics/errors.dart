sealed class ReaderNextLoadError {
  const ReaderNextLoadError();

  String get title;
  String get userMessage;
  String get diagnosticCode;
  bool get retryable;
  bool get exportLogsSuggested;
}

final class ReaderNextSourceBoundaryError extends ReaderNextLoadError {
  const ReaderNextSourceBoundaryError({
    required this.userMessage,
    required this.diagnosticCode,
  });

  @override
  final String userMessage;

  @override
  final String diagnosticCode;

  @override
  String get title => 'Identity Boundary Error';

  @override
  bool get retryable => true;

  @override
  bool get exportLogsSuggested => true;
}

final class ReaderNextSourceUnavailableError extends ReaderNextLoadError {
  const ReaderNextSourceUnavailableError({
    required this.userMessage,
    required this.diagnosticCode,
  });

  @override
  final String userMessage;

  @override
  final String diagnosticCode;

  @override
  String get title => 'Source Unavailable';

  @override
  bool get retryable => true;

  @override
  bool get exportLogsSuggested => true;
}

final class ReaderNextValidationError extends ReaderNextLoadError {
  const ReaderNextValidationError({
    required this.userMessage,
    required this.diagnosticCode,
  });

  @override
  final String userMessage;

  @override
  final String diagnosticCode;

  @override
  String get title => 'Invalid Reader State';

  @override
  bool get retryable => false;

  @override
  bool get exportLogsSuggested => true;
}

final class ReaderNextUnknownError extends ReaderNextLoadError {
  const ReaderNextUnknownError({
    required this.userMessage,
    required this.diagnosticCode,
  });

  @override
  final String userMessage;

  @override
  final String diagnosticCode;

  @override
  String get title => 'Error';

  @override
  bool get retryable => true;

  @override
  bool get exportLogsSuggested => true;
}
