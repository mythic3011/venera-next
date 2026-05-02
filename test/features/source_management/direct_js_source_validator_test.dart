import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';

void main() {
  test('direct javascript source rejects invalid url', () async {
    final validator = DirectJsSourceValidator(
      fetcher: (_) async => const DirectJsFetchResponse(statusCode: 200, body: ''),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: 'demo'),
    );

    final result = await validator.validate('::::');

    expect(result, isA<SourceCommandFailed>());
    expect((result as SourceCommandFailed).code, sourceScriptUrlInvalidCode);
  });

  test('direct javascript source rejects relative url as invalid', () async {
    final validator = DirectJsSourceValidator(
      fetcher: (_) async => const DirectJsFetchResponse(statusCode: 200, body: ''),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: 'demo'),
    );

    final result = await validator.validate('abc');

    expect(result, isA<SourceCommandFailed>());
    expect((result as SourceCommandFailed).code, sourceScriptUrlInvalidCode);
  });

  test('direct javascript source rejects non https url by default', () async {
    final validator = DirectJsSourceValidator(
      fetcher: (_) async => const DirectJsFetchResponse(statusCode: 200, body: ''),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: 'demo'),
    );

    final result = await validator.validate('http://example.com/source.js');

    expect(result, isA<SourceCommandFailed>());
    expect((result as SourceCommandFailed).code, sourceScriptUrlInsecureCode);
  });

  test('direct javascript source rejects html response masquerading as script', () async {
    final validator = DirectJsSourceValidator(
      fetcher: (_) async => const DirectJsFetchResponse(
        statusCode: 200,
        body: '<!doctype html><html><body>blocked</body></html>',
        contentType: 'text/html',
      ),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: 'demo'),
    );

    final result = await validator.validate('https://example.com/source.js');

    expect(result, isA<SourceCommandFailed>());
    expect(
      (result as SourceCommandFailed).code,
      sourceScriptContentTypeInvalidCode,
    );
  });

  test('direct javascript source enforces script size limit', () async {
    final validator = DirectJsSourceValidator(
      maxScriptBytes: 8,
      fetcher: (_) async => const DirectJsFetchResponse(
        statusCode: 200,
        body: 'const veryLongScript = "0123456789";',
        contentType: 'application/javascript',
      ),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: 'demo'),
    );

    final result = await validator.validate('https://example.com/source.js');

    expect(result, isA<SourceCommandFailed>());
    expect((result as SourceCommandFailed).code, sourceScriptTooLargeCode);
  });

  test('direct javascript source enforces UTF-8 byte size limit', () async {
    final validator = DirectJsSourceValidator(
      maxScriptBytes: 5,
      fetcher: (_) async => const DirectJsFetchResponse(
        statusCode: 200,
        body: '你你你',
        contentType: 'application/javascript',
      ),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: 'demo'),
    );

    final result = await validator.validate('https://example.com/source.js');

    expect(result, isA<SourceCommandFailed>());
    expect((result as SourceCommandFailed).code, sourceScriptTooLargeCode);
  });

  test('direct javascript source maps fetch exceptions to typed fetch failure', () async {
    final validator = DirectJsSourceValidator(
      fetcher: (_) async => throw Exception('network failed'),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: 'demo'),
    );

    final result = await validator.validate('https://example.com/source.js');

    expect(result, isA<SourceCommandFailed>());
    expect((result as SourceCommandFailed).code, sourceScriptFetchFailedCode);
  });

  test('direct javascript validation runs outside ui isolate with timeout', () async {
    var portCalls = 0;
    final validator = DirectJsSourceValidator(
      validationTimeout: const Duration(milliseconds: 10),
      fetcher: (_) async => const DirectJsFetchResponse(
        statusCode: 200,
        body: 'sourceKey = "demo";',
        contentType: 'application/javascript',
      ),
      isolatedValidationPort: (_) async {
        portCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const DirectJsValidationMetadata(sourceKey: 'demo');
      },
    );

    final result = await validator.validate('https://example.com/source.js');

    expect(portCalls, 1);
    expect(result, isA<SourceCommandFailed>());
    expect(
      (result as SourceCommandFailed).code,
      sourceScriptValidationTimeoutCode,
    );
  });

  test('direct javascript validation returns SOURCE_KEY_MISSING when key absent', () async {
    final validator = DirectJsSourceValidator(
      fetcher: (_) async => const DirectJsFetchResponse(
        statusCode: 200,
        body: 'const source = {};',
        contentType: 'application/javascript',
      ),
      isolatedValidationPort: (_) async =>
          const DirectJsValidationMetadata(sourceKey: '   '),
    );

    final result = await validator.validate('https://example.com/source.js');

    expect(result, isA<SourceCommandFailed>());
    expect((result as SourceCommandFailed).code, sourceKeyMissingCode);
  });
}
