import 'dart:convert';
import 'dart:async';

class DirectJsFetchResponse {
  const DirectJsFetchResponse({
    required this.statusCode,
    required this.body,
    this.contentType,
  });

  final int statusCode;
  final String body;
  final String? contentType;
}

class DirectJsValidationMetadata {
  const DirectJsValidationMetadata({
    required this.sourceKey,
    this.name,
    this.version,
  });

  final String sourceKey;
  final String? name;
  final String? version;
}

sealed class SourceCommandResult {
  const SourceCommandResult();
}

class SourceCommandSuccess extends SourceCommandResult {
  const SourceCommandSuccess({required this.metadata});

  final DirectJsValidationMetadata metadata;
}

class SourceCommandFailed extends SourceCommandResult {
  const SourceCommandFailed({required this.code, required this.message});

  final String code;
  final String message;
}

typedef DirectJsFetcher = Future<DirectJsFetchResponse> Function(String url);
typedef DirectJsIsolatedValidationPort =
    Future<DirectJsValidationMetadata> Function(String script);

const sourceScriptUrlInvalidCode = 'SOURCE_SCRIPT_URL_INVALID';
const sourceScriptUrlInsecureCode = 'SOURCE_SCRIPT_URL_INSECURE';
const sourceScriptFetchFailedCode = 'SOURCE_SCRIPT_FETCH_FAILED';
const sourceScriptContentTypeInvalidCode = 'SOURCE_SCRIPT_CONTENT_TYPE_INVALID';
const sourceScriptTooLargeCode = 'SOURCE_SCRIPT_TOO_LARGE';
const sourceScriptValidationTimeoutCode = 'SOURCE_SCRIPT_VALIDATION_TIMEOUT';
const sourceScriptSchemaInvalidCode = 'SOURCE_SCRIPT_SCHEMA_INVALID';
const sourceKeyMissingCode = 'SOURCE_KEY_MISSING';

class DirectJsSourceValidator {
  DirectJsSourceValidator({
    required DirectJsFetcher fetcher,
    required DirectJsIsolatedValidationPort isolatedValidationPort,
    this.validationTimeout = const Duration(seconds: 8),
    this.maxScriptBytes = 1024 * 1024,
  }) : _fetcher = fetcher,
       _isolatedValidationPort = isolatedValidationPort;

  final DirectJsFetcher _fetcher;
  final DirectJsIsolatedValidationPort _isolatedValidationPort;
  final Duration validationTimeout;
  final int maxScriptBytes;

  Future<SourceCommandResult> validate(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return const SourceCommandFailed(
        code: sourceScriptUrlInvalidCode,
        message: 'Source script URL is invalid',
      );
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return const SourceCommandFailed(
        code: sourceScriptUrlInsecureCode,
        message: 'Source script URL must use HTTPS',
      );
    }

    late final DirectJsFetchResponse response;
    try {
      response = await _fetcher(uri.toString());
    } catch (_) {
      return const SourceCommandFailed(
        code: sourceScriptFetchFailedCode,
        message: 'Failed to fetch direct JavaScript source',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return SourceCommandFailed(
        code: sourceScriptFetchFailedCode,
        message: 'HTTP ${response.statusCode} while fetching direct JavaScript',
      );
    }

    final body = response.body;
    final lowerContentType = (response.contentType ?? '').toLowerCase();
    if (_looksLikeHtml(body) || lowerContentType.contains('text/html')) {
      return const SourceCommandFailed(
        code: sourceScriptContentTypeInvalidCode,
        message: 'Direct JavaScript validation rejected HTML response',
      );
    }

    if (utf8.encode(body).length > maxScriptBytes) {
      return SourceCommandFailed(
        code: sourceScriptTooLargeCode,
        message: 'Direct JavaScript exceeds configured size limit',
      );
    }

    try {
      final metadata = await _isolatedValidationPort(
        body,
      ).timeout(validationTimeout);
      if (metadata.sourceKey.trim().isEmpty) {
        return const SourceCommandFailed(
          code: sourceKeyMissingCode,
          message: 'Source metadata missing source key',
        );
      }
      return SourceCommandSuccess(metadata: metadata);
    } on TimeoutException {
      return const SourceCommandFailed(
        code: sourceScriptValidationTimeoutCode,
        message: 'Direct JavaScript validation timed out',
      );
    } catch (_) {
      return const SourceCommandFailed(
        code: sourceScriptSchemaInvalidCode,
        message: 'Direct JavaScript validation failed',
      );
    }
  }

  bool _looksLikeHtml(String body) {
    final probe = body.trimLeft().toLowerCase();
    return probe.startsWith('<!doctype html') ||
        probe.startsWith('<html') ||
        probe.contains('<body');
  }
}
