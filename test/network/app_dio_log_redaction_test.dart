import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/app_dio.dart';

void main() {
  test(
    'redactHeadersForLog masks default sensitive headers case-insensitively',
    () {
      final headers = {
        'Authorization': 'Bearer abc',
        'cookie': 'sid=1',
        'X-API-KEY': 'secret',
        'Accept': 'application/json',
      };

      final masked = redactHeadersForLog(headers);

      expect(masked['Authorization'], '********');
      expect(masked['cookie'], '********');
      expect(masked['X-API-KEY'], '********');
      expect(masked['Accept'], 'application/json');
    },
  );

  test('redactHeadersForLog preserves additive maskHeadersInLog behavior', () {
    final headers = {'X-Custom': 'value', 'X-Trace': 'trace-id'};

    final masked = redactHeadersForLog(
      headers,
      maskHeadersInLog: const ['x-custom'],
    );

    expect(masked['X-Custom'], '********');
    expect(masked['X-Trace'], 'trace-id');
  });
}
