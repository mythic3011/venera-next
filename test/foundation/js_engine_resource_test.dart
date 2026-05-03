import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/js_engine.dart';

void main() {
  group('JSAutoFreeFunction', () {
    test('duplicates and delegates calls', () {
      final func = _FakeInvokable((args) => args.join(':'));

      final autoFree = JSAutoFreeFunction(func);

      expect(func.dupCount, 1);
      expect(autoFree(['a', 'b']), 'a:b');
      expect(func.invocations, [
        ['a', 'b'],
      ]);
    });

    test('dispose destroys once and is idempotent', () {
      final func = _FakeInvokable((args) => args);
      final autoFree = JSAutoFreeFunction(func);

      autoFree.dispose();
      autoFree.dispose();

      expect(func.destroyCount, 1);
    });

    test('call after dispose fails closed', () {
      final func = _FakeInvokable((args) => args);
      final autoFree = JSAutoFreeFunction(func);

      autoFree.dispose();

      expect(
        () => autoFree([]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'JSAutoFreeFunction has been disposed',
          ),
        ),
      );
    });
  });

  group('HTML bridge resource safety', () {
    test('missing document through bridge returns typed bridge error', () {
      final result = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'querySelector',
        'key': 9010,
        'query': 'p',
      });

      _expectBridgeError(result, 'html');
    });

    test('non-string selector through bridge returns typed bridge error', () {
      final docKey = 9011;
      _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'parse',
        'key': docKey,
        'data': '<p>Hello</p>',
      });

      final result = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'querySelector',
        'key': docKey,
        'query': 1,
      });

      _expectBridgeError(result, 'html');
    });

    test('non-int parse key through bridge returns typed bridge error', () {
      final result = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'parse',
        'key': 'doc',
        'data': '<p>Hello</p>',
      });

      _expectBridgeError(result, 'html');
    });

    test('valid parse, query, and getText still works', () {
      final docKey = 9012;
      _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'parse',
        'key': docKey,
        'data': '<main><p class="title">Hello</p></main>',
      });

      final elementKey = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'querySelector',
        'key': docKey,
        'query': '.title',
      });
      final text = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'getText',
        'doc': docKey,
        'key': elementKey,
      });

      expect(text, 'Hello');
    });

    test('direct negative element key throws JavaScriptRuntimeException', () {
      final document = DocumentWrapper.parse('<p>Hello</p>');

      expect(
        () => document.elementGetText(-1),
        throwsA(isA<JavaScriptRuntimeException>()),
      );
    });

    test('missing element key through bridge returns typed bridge error', () {
      final docKey = 9013;
      _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'parse',
        'key': docKey,
        'data': '<p>Hello</p>',
      });

      final result = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'getText',
        'doc': docKey,
        'key': 99,
      });

      _expectBridgeError(result, 'html');
    });

    test('missing node key through bridge returns typed bridge error', () {
      final docKey = 9014;
      _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'parse',
        'key': docKey,
        'data': '<div id="root"><span>Hello</span></div>',
      });
      final elementKey = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'getElementById',
        'key': docKey,
        'id': 'root',
      });
      _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'getNodes',
        'doc': docKey,
        'key': elementKey,
      });

      final result = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'node_type',
        'doc': docKey,
        'key': 99,
      });

      _expectBridgeError(result, 'html');
    });

    test('valid node flow still works', () {
      final docKey = 9015;
      _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'parse',
        'key': docKey,
        'data': '<div id="root"><span>Hello</span>tail</div>',
      });
      final elementKey = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'querySelector',
        'key': docKey,
        'query': '#root',
      });
      final nodeKeys =
          _bridge(<String, dynamic>{
                'method': 'html',
                'function': 'getNodes',
                'doc': docKey,
                'key': elementKey,
              })
              as List<int>;

      final nodeType = _bridge(<String, dynamic>{
        'method': 'html',
        'function': 'node_type',
        'doc': docKey,
        'key': nodeKeys.first,
      });

      expect(nodeType, 'element');
    });
  });
}

Object? _bridge(Map<String, dynamic> message) {
  return JsEngine().handleBridgeMessageForTesting(message);
}

void _expectBridgeError(Object? result, String method) {
  expect(result, isA<Map<String, dynamic>>());
  final map = result as Map<String, dynamic>;
  expect(map['ok'], isFalse);
  expect(map['code'], 'bridge_error');
  expect(map['method'], method);
}

class _FakeInvokable extends JSInvokable {
  _FakeInvokable(this._callback);

  final Object? Function(List args) _callback;

  int dupCount = 0;
  int destroyCount = 0;
  final invocations = <List<dynamic>>[];

  @override
  void dup() {
    dupCount++;
    super.dup();
  }

  @override
  void destroy() {
    destroyCount++;
  }

  @override
  Object? invoke(List args, [dynamic thisVal]) {
    invocations.add(List<dynamic>.from(args));
    return _callback(args);
  }
}
