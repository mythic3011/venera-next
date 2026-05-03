import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/js_engine.dart';

void main() {
  test('http bridge blocks non-http scheme', () {
    final result = JsEngine().handleBridgeMessageForTesting(<String, dynamic>{
      'method': 'http',
      'url': 'ftp://example.com/a',
      'http_method': 'GET',
    });
    expect(result, isA<Map<String, dynamic>>());
    final map = result as Map<String, dynamic>;
    expect(map['ok'], isFalse);
    expect(map['code'], 'bridge_error');
    expect(map['method'], 'http');
  });

  test('http bridge blocks localhost target by default', () {
    final result = JsEngine().handleBridgeMessageForTesting(<String, dynamic>{
      'method': 'http',
      'url': 'http://localhost:8080/health',
      'http_method': 'GET',
    });
    expect(result, isA<Map<String, dynamic>>());
    final map = result as Map<String, dynamic>;
    expect(map['ok'], isFalse);
    expect(map['code'], 'bridge_error');
    expect(map['method'], 'http');
  });

  test('http bridge blocks private ipv4 target by default', () {
    final result = JsEngine().handleBridgeMessageForTesting(<String, dynamic>{
      'method': 'http',
      'url': 'http://192.168.1.10/api',
      'http_method': 'GET',
    });
    expect(result, isA<Map<String, dynamic>>());
    final map = result as Map<String, dynamic>;
    expect(map['ok'], isFalse);
    expect(map['code'], 'bridge_error');
    expect(map['method'], 'http');
  });
}
