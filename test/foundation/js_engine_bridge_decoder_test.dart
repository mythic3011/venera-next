import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/js_engine.dart';

void main() {
  test('JsBridgeRequest.tryParse rejects non-map and missing method', () {
    expect(JsBridgeRequest.tryParse(null), isNull);
    expect(JsBridgeRequest.tryParse('x'), isNull);
    expect(JsBridgeRequest.tryParse(<String, dynamic>{}), isNull);
    expect(JsBridgeRequest.tryParse(<String, dynamic>{'method': 1}), isNull);
  });

  test('JsBridgeRequest.tryParse accepts valid map', () {
    final request = JsBridgeRequest.tryParse(<String, dynamic>{
      'method': 'log',
      'title': 't',
    });
    expect(request, isNotNull);
    expect(request!.method, 'log');
    expect(request.payload['title'], 't');
  });

  test('bridge returns typed error for malformed envelope', () {
    final result = JsEngine().handleBridgeMessageForTesting('bad-envelope');
    expect(result, isA<Map<String, dynamic>>());
    final map = result as Map<String, dynamic>;
    expect(map['ok'], isFalse);
    expect(map['code'], 'malformed_request');
  });

  test('bridge returns typed error for malformed method payload', () {
    final result = JsEngine().handleBridgeMessageForTesting(<String, dynamic>{
      'method': 'load_data',
      'key': 123,
      'data_key': 'v',
    });
    expect(result, isA<Map<String, dynamic>>());
    final map = result as Map<String, dynamic>;
    expect(map['ok'], isFalse);
    expect(map['code'], 'bridge_error');
    expect(map['method'], 'load_data');
  });
}
