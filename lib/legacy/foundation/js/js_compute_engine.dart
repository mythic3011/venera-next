import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_qjs/flutter_qjs.dart';

class JsComputeEngine {
  FlutterQjs? _engine;
  bool _initialized = false;

  Future<void> init(Uint8List jsInit) async {
    if (_initialized) return;
    final engine = FlutterQjs();
    engine.dispatch();
    engine.evaluate(utf8.decode(jsInit), name: '<compute-init>');
    _engine = engine;
    _initialized = true;
  }

  dynamic runCode(String js, [String? name]) {
    final engine = _engine;
    if (!_initialized || engine == null) {
      throw StateError('JsComputeEngine is not initialized');
    }
    return engine.evaluate(js, name: name);
  }

  void dispose() {
    final engine = _engine;
    _engine = null;
    _initialized = false;
    try {
      engine?.close();
      engine?.port.close();
    } catch (_) {
      // Best effort cleanup.
    }
  }
}
