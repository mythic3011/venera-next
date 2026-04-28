enum SourceRefDiagnosticCode {
  sourceRefNotFound,
  sourceRefTypeMismatch,
  sourceRefHandlerMismatch,
  sourceNotAvailable,
  localAssetMissing,
}

class SourceRefDiagnostic implements Exception {
  final SourceRefDiagnosticCode code;
  final String message;
  final Map<String, Object?> context;

  const SourceRefDiagnostic(this.code, this.message, {this.context = const {}});

  @override
  String toString() =>
      'SourceRefDiagnostic(code: $code, message: $message, context: $context)';
}
