const _redactedValue = '<redacted>';
const _redactedScriptContent = '<redacted_script_content>';

const Set<String> _sensitiveKeys = <String>{
  'authorization',
  'cookie',
  'set-cookie',
  'x-auth-signature',
  'x-auth-timestamp',
  'deviceinfo',
  'device',
  'pseudoid',
  'umstring',
  'token',
  'session',
  'password',
  'signature',
};

Map<String, Object?> redactSourceDiagnosticData(Map<String, Object?> input) {
  final output = <String, Object?>{};
  for (final entry in input.entries) {
    final lower = entry.key.toLowerCase();
    final value = entry.value;
    if (_sensitiveKeys.contains(lower)) {
      output[entry.key] = _redactedValue;
      continue;
    }
    if (lower == 'headers' && value is Map) {
      output[entry.key] = _redactMapCaseInsensitive(value);
      continue;
    }
    if (lower == 'url' && value is String) {
      final parsed = Uri.tryParse(value);
      output[entry.key] = parsed == null
          ? value
          : redactSourceDiagnosticUri(parsed).toString();
      continue;
    }
    output[entry.key] = value;
  }
  return output;
}

Uri redactSourceDiagnosticUri(Uri uri) {
  if (uri.queryParameters.isEmpty) {
    return uri;
  }
  final redactedParams = <String, String>{};
  for (final entry in uri.queryParameters.entries) {
    final lower = entry.key.toLowerCase();
    redactedParams[entry.key] = _sensitiveKeys.contains(lower)
        ? _redactedValue
        : entry.value;
  }
  return uri.replace(queryParameters: redactedParams);
}

String redactSourceScriptForDiagnostics(String _) {
  return _redactedScriptContent;
}

Map<String, Object?> _redactMapCaseInsensitive(Map input) {
  final redacted = <String, Object?>{};
  for (final entry in input.entries) {
    final key = entry.key.toString();
    final lower = key.toLowerCase();
    redacted[key] = _sensitiveKeys.contains(lower) ? _redactedValue : entry.value;
  }
  return redacted;
}
