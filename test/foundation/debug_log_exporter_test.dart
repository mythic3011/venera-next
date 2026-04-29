import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/debug_log_exporter.dart';
import 'package:venera/foundation/log.dart';

void main() {
  final exporter = DebugLogExporter();

  Future<HttpClientResponse> getUri(Uri uri, {String method = 'GET'}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      return await request.close();
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> responseJson(HttpClientResponse response) async {
    final body = await utf8.decoder.bind(response).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  setUp(() {
    Log.clear();
  });

  tearDown(() async {
    await exporter.stop();
    await Log.closeFileSink();
  });

  test('start binds loopback random port and exposes token', () async {
    await exporter.start();

    expect(exporter.isRunning, isTrue);
    expect(exporter.baseUri, isNotNull);
    expect(exporter.baseUri!.host, '127.0.0.1');
    expect(exporter.baseUri!.port, greaterThan(0));
    expect(exporter.token, isNotNull);
    expect(exporter.token!.length, greaterThanOrEqualTo(32));
  });

  test('/health with valid token returns expected payload', () async {
    Log.info('a', 'b');
    await exporter.start();

    final response = await getUri(exporter.healthUri()!);
    final json = await responseJson(response);

    expect(response.statusCode, HttpStatus.ok);
    expect(json['ok'], true);
    expect(json['platform'], isA<String>());
    expect(json['logCount'], Log.logs.length);
  });

  test('missing or wrong token returns 403', () async {
    await exporter.start();

    final missing = await getUri(exporter.baseUri!.replace(path: '/health'));
    expect(missing.statusCode, HttpStatus.forbidden);

    final wrong = await getUri(
      exporter.baseUri!.replace(
        path: '/health',
        queryParameters: {'token': 'wrong'},
      ),
    );
    expect(wrong.statusCode, HttpStatus.forbidden);
  });

  test('unknown route returns 404 and non-GET returns 405', () async {
    await exporter.start();

    final unknown = await getUri(
      exporter.baseUri!.replace(
        path: '/unknown',
        queryParameters: {'token': exporter.token!},
      ),
    );
    expect(unknown.statusCode, HttpStatus.notFound);

    final post = await getUri(exporter.healthUri()!, method: 'POST');
    expect(post.statusCode, HttpStatus.methodNotAllowed);
  });

  test('/logs newest level filter, limit clamp, and redaction', () async {
    Log.info('Info', 'https://example.com/path?token=abc');
    Log.error('Error', 'password=secret authorization=abc');
    Log.error('Header', 'Authorization: Bearer token-value');

    await exporter.start();

    final logsResponse = await getUri(
      exporter.logsUri(level: 'error', limit: 5000)!,
    );
    final logsJson = await responseJson(logsResponse);

    expect(logsResponse.statusCode, HttpStatus.ok);
    expect(logsJson['limit'], 1000);
    expect(logsJson['count'], 2);

    final logs = (logsJson['logs'] as List).cast<Map<String, dynamic>>();
    expect(logs.every((e) => e['level'] == 'error'), isTrue);

    final contentJoined = logs
        .map((e) => '${e['title']} ${e['content']}')
        .join(' ');
    expect(contentJoined.contains('password=secret'), isFalse);
    expect(contentJoined.contains('authorization=abc'), isFalse);
    expect(contentJoined.contains('Bearer token-value'), isFalse);
    expect(contentJoined.contains('[redacted]'), isTrue);
  });

  test(
    '/logs includes persisted entries after session logs are cleared',
    () async {
      final oldInitialized = App.isInitialized;
      final oldDataPath = oldInitialized ? App.dataPath : null;
      final oldExternal = App.externalStoragePath;

      final dir = await Directory.systemTemp.createTemp(
        'venera_debug_exporter_persisted_test_',
      );
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;

      final persistedFile = File(Log.logFilePath!);
      await persistedFile.parent.create(recursive: true);
      await persistedFile.writeAsString(
        'error Image Loading 2026-04-30 01:47:32.082278 \n'
        'Bad state: Cannot load relative thumbnail URL without a valid absolute source URL.\n\n',
      );
      Log.clear();
      await exporter.start();

      final logsResponse = await getUri(exporter.logsUri(level: 'error')!);
      final logsJson = await responseJson(logsResponse);
      final logs = (logsJson['logs'] as List).cast<Map<String, dynamic>>();

      expect(logsResponse.statusCode, HttpStatus.ok);
      expect(logs.length, 1);
      expect(logs.first['source'], 'persisted');
      expect(logs.first['title'], 'Image Loading');
      expect(logs.first['content'], contains('relative thumbnail URL'));
      expect((logsJson['sources'] as Map)['persisted'], 1);

      await exporter.stop();
      await dir.delete(recursive: true);
      if (oldInitialized && oldDataPath != null) {
        App.dataPath = oldDataPath;
      }
      App.externalStoragePath = oldExternal;
      App.isInitialized = oldInitialized;
    },
  );

  test('/diagnostics includes expected shape and excludes token', () async {
    Log.error('Err', 'session=abc');
    await exporter.start();

    final response = await getUri(exporter.diagnosticsUri()!);
    final json = await responseJson(response);

    expect(response.statusCode, HttpStatus.ok);
    expect(json['platform'], isA<Map>());
    expect(json['runtime'], isA<Map>());
    expect(json['debugServer'], isA<Map>());
    expect(json['paths'], isA<Map>());
    expect(json['logs'], isA<Map>());

    final encoded = jsonEncode(json);
    expect(encoded.contains(exporter.token!), isFalse);
  });

  test('stop clears running state, token, and baseUri', () async {
    await exporter.start();
    expect(exporter.isRunning, isTrue);
    expect(exporter.baseUri, isNotNull);
    expect(exporter.token, isNotNull);

    await exporter.stop();

    expect(exporter.isRunning, isFalse);
    expect(exporter.baseUri, isNull);
    expect(exporter.token, isNull);
  });

  test('diagnostics redacts url query and secrets', () async {
    await exporter.start();
    Log.error('url', 'http://host/a?account=abc&x=1');

    final response = await getUri(exporter.diagnosticsUri()!);
    final json = await responseJson(response);
    final encoded = jsonEncode(json);

    expect(encoded.contains('account=abc'), isFalse);
    expect(encoded.contains('?account=abc'), isFalse);
    expect(encoded.contains('[redacted]'), isTrue);
  });

  test('desktop-only assumption is valid for this test runtime', () {
    expect(
      App.isDesktop,
      isTrue,
      reason:
          'This exporter MVP is desktop-only and tests run on desktop CI/runtime.',
    );
  });
}
