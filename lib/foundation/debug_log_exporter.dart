import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/log.dart';

class DebugLogExporter {
  DebugLogExporter._();

  static final DebugLogExporter _instance = DebugLogExporter._();

  factory DebugLogExporter() => _instance;

  HttpServer? _server;
  Uri? _baseUri;
  String? _token;

  bool get isRunning => _server != null;

  Uri? get baseUri => _baseUri;

  String? get token => _token;

  Future<void> start() async {
    if (isRunning) {
      return;
    }
    if (!App.isDesktop) {
      throw UnsupportedError('Diagnostics server is only supported on desktop');
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _token = _generateToken();
    _baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    _server = server;
    server.listen(_handleRequest);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _baseUri = null;
    _token = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Uri? logsUri({String level = 'all', int limit = 200}) {
    if (_baseUri == null || _token == null) {
      return null;
    }
    return _baseUri!.replace(
      path: '/logs',
      queryParameters: {'token': _token!, 'level': level, 'limit': '$limit'},
    );
  }

  Uri? diagnosticsUri() {
    if (_baseUri == null || _token == null) {
      return null;
    }
    return _baseUri!.replace(
      path: '/diagnostics',
      queryParameters: {'token': _token!},
    );
  }

  Uri? healthUri() {
    if (_baseUri == null || _token == null) {
      return null;
    }
    return _baseUri!.replace(
      path: '/health',
      queryParameters: {'token': _token!},
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET') {
      return _writeJson(request.response, HttpStatus.methodNotAllowed, {
        'error': 'Method Not Allowed',
      });
    }

    if (!_isTokenValid(request.uri.queryParameters['token'])) {
      return _writeJson(request.response, HttpStatus.forbidden, {
        'error': 'Forbidden',
      });
    }

    switch (request.uri.path) {
      case '/health':
        return _writeJson(request.response, HttpStatus.ok, {
          'ok': true,
          'platform': _platformName(),
          'logCount': Log.logs.length,
        });
      case '/logs':
        final level = request.uri.queryParameters['level'] ?? 'all';
        final limit = _parseLimit(request.uri.queryParameters['limit']);
        final logs = Log.newest(level: level, limit: limit)
            .map((item) => Log.serialize(item))
            .map(
              (item) => {
                'level': item['level'],
                'title': redactLogText((item['title'] ?? '').toString()),
                'content': redactLogText((item['content'] ?? '').toString()),
                'time': item['time'],
              },
            )
            .toList();
        return _writeJson(request.response, HttpStatus.ok, {
          'logs': logs,
          'count': logs.length,
          'limit': limit,
        });
      case '/diagnostics':
        final newestErrors = Log.newest(level: 'error', limit: 20)
            .map((item) => Log.serialize(item))
            .map(
              (item) => {
                'level': item['level'],
                'title': redactLogText((item['title'] ?? '').toString()),
                'content': redactLogText((item['content'] ?? '').toString()),
                'time': item['time'],
              },
            )
            .toList();
        final diagnostics = {
          'platform': {'os': _platformName(), 'isDesktop': App.isDesktop},
          'runtime': {'appVersion': App.version},
          'debugServer': {
            'running': isRunning,
            'baseUrl': _baseUri?.toString(),
          },
          'paths': {
            'dataPath': App.isInitialized ? App.dataPath : null,
            'cachePath': App.isInitialized ? App.cachePath : null,
          },
          'logs': {
            'totalCount': Log.logs.length,
            'recentErrorCount': Log.newest(level: 'error', limit: 200).length,
            'newestErrors': newestErrors,
          },
        };
        return _writeJson(
          request.response,
          HttpStatus.ok,
          redactForDiagnostics(diagnostics),
        );
      default:
        return _writeJson(request.response, HttpStatus.notFound, {
          'error': 'Not Found',
        });
    }
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Object? body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    response.write(jsonEncode(body));
    await response.close();
  }

  bool _isTokenValid(String? candidate) {
    return _token != null && candidate != null && candidate == _token;
  }

  int _parseLimit(String? value) {
    final parsed = int.tryParse(value ?? '') ?? 200;
    if (parsed < 1) return 1;
    if (parsed > 1000) return 1000;
    return parsed;
  }

  String _platformName() {
    if (App.isMacOS) return 'macos';
    if (App.isWindows) return 'windows';
    if (App.isLinux) return 'linux';
    if (App.isAndroid) return 'android';
    if (App.isIOS) return 'ios';
    return 'unknown';
  }

  String _generateToken() {
    final bytes = Uint8List(32);
    final random = Random.secure();
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Object? redactForDiagnostics(Object? value) {
    if (value is String) {
      return redactLogText(value);
    }
    if (value is Map) {
      return value.map((key, val) {
        return MapEntry(key, redactForDiagnostics(val));
      });
    }
    if (value is List) {
      return value.map(redactForDiagnostics).toList();
    }
    return value;
  }

  String redactLogText(String text) {
    var redacted = redactUrlQuery(text);

    redacted = redacted.replaceAllMapped(
      RegExp(
        r'^\s*(authorization)\s*:\s*.+$',
        caseSensitive: false,
        multiLine: true,
      ),
      (match) => '${match.group(1)}: [redacted]',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(r'^\s*(cookie)\s*:\s*.+$', caseSensitive: false, multiLine: true),
      (match) => '${match.group(1)}: [redacted]',
    );

    final secretPattern = RegExp(
      r'\b(token|access_token|refresh_token|password|passwd|cookie|authorization|auth|account|session)\s*=\s*[^\s&;]+',
      caseSensitive: false,
    );
    redacted = redacted.replaceAllMapped(secretPattern, (match) {
      final source = match.group(0)!;
      final index = source.indexOf('=');
      if (index == -1) {
        return '[redacted]';
      }
      final key = source.substring(0, index);
      return '$key=[redacted]';
    });

    return redacted;
  }

  String redactUrlQuery(String text) {
    return text.replaceAllMapped(
      RegExp("https?://[^\\s\\]\\)\"']+\\?[^\\s\\]\\)\"']*"),
      (match) {
        final raw = match.group(0)!;
        final qIndex = raw.indexOf('?');
        if (qIndex == -1) {
          return raw;
        }
        return '${raw.substring(0, qIndex)}?[redacted]';
      },
    );
  }
}
