import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:venera/foundation/js/js_compute_engine.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

class JSPool {
  static const int _maxInstances = 4;
  static const Duration _defaultTaskTimeout = Duration(seconds: 20);
  static const Duration _workerReadyTimeout = Duration(seconds: 10);

  final List<IsolateJsEngine> _instances = <IsolateJsEngine>[];
  Future<void>? _initFuture;
  Uint8List? _jsInit;

  static final JSPool _singleton = JSPool._internal();

  factory JSPool() => _singleton;

  JSPool._internal();

  Future<void> init() {
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    final jsInitBuffer = await rootBundle.load('assets/init.js');
    _jsInit = jsInitBuffer.buffer.asUint8List();

    final workers = <IsolateJsEngine>[];
    try {
      for (var i = 0; i < _maxInstances; i++) {
        final worker = IsolateJsEngine(
          id: i,
          jsInit: _jsInit!,
          readyTimeout: _workerReadyTimeout,
        );
        await worker.ready;
        workers.add(worker);
      }
      _instances
        ..clear()
        ..addAll(workers);
    } catch (e, s) {
      for (final worker in workers) {
        await worker.close(force: true);
      }
      _initFuture = null;
      AppDiagnostics.error('js.pool', e, stackTrace: s, message: 'initialize_js_pool_failed');
      rethrow;
    }
  }

  Future<dynamic> execute(
    String jsFunction,
    List<dynamic> args, {
    Duration timeout = _defaultTaskTimeout,
    String? sourceKey,
  }) async {
    await init();
    if (_instances.isEmpty) {
      throw StateError('JSPool has no active JS workers');
    }
    var selected = _selectWorker();
    if (selected.isClosed || selected.isFailed) {
      selected = await _replaceWorker(selected);
    }
    return selected.execute(
      jsFunction,
      args,
      timeout: timeout,
      sourceKey: sourceKey,
    );
  }

  IsolateJsEngine _selectWorker() {
    return _instances.reduce((a, b) {
      if (a.isClosed || a.isFailed) return b;
      if (b.isClosed || b.isFailed) return a;
      return a.pendingTasks <= b.pendingTasks ? a : b;
    });
  }

  Future<IsolateJsEngine> _replaceWorker(IsolateJsEngine oldWorker) async {
    final index = _instances.indexOf(oldWorker);
    if (index == -1) {
      throw StateError('Worker is not part of this pool');
    }
    await oldWorker.close(force: true);
    final jsInit = _jsInit;
    if (jsInit == null) {
      _initFuture = null;
      await init();
      return _selectWorker();
    }
    final replacement = IsolateJsEngine(
      id: oldWorker.id,
      jsInit: jsInit,
      readyTimeout: _workerReadyTimeout,
    );
    await replacement.ready;
    _instances[index] = replacement;
    return replacement;
  }

  Future<void> dispose() async {
    final workers = List<IsolateJsEngine>.from(_instances);
    _instances.clear();
    _initFuture = null;
    await Future.wait(
      workers.map((worker) => worker.close(force: true)),
      eagerError: false,
    );
  }
}

class _IsolateJsEngineInitParam {
  final int id;
  final SendPort sendPort;
  final Uint8List jsInit;

  const _IsolateJsEngineInitParam({
    required this.id,
    required this.sendPort,
    required this.jsInit,
  });
}

class IsolateJsEngine {
  final int id;
  final Duration readyTimeout;

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  int _counter = 0;
  final Map<int, Completer<dynamic>> _tasks = <int, Completer<dynamic>>{};
  final Map<int, Timer> _taskTimers = <int, Timer>{};
  final Completer<void> _readyCompleter = Completer<void>();
  bool _isClosed = false;
  bool _isFailed = false;

  Future<void> get ready => _readyCompleter.future;

  int get pendingTasks => _tasks.length;

  bool get isClosed => _isClosed;

  bool get isFailed => _isFailed;

  IsolateJsEngine({
    required this.id,
    required Uint8List jsInit,
    required this.readyTimeout,
  }) {
    unawaited(_start(jsInit));
  }

  Future<void> _start(Uint8List jsInit) async {
    _receivePort = ReceivePort();
    _receivePort!.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) {
        _failAll(error, stackTrace);
      },
      onDone: () {
        if (!_isClosed) {
          _failAll(StateError('Worker receive port closed unexpectedly'));
        }
      },
    );

    try {
      _isolate = await Isolate.spawn(
        _run,
        _IsolateJsEngineInitParam(
          id: id,
          sendPort: _receivePort!.sendPort,
          jsInit: jsInit,
        ),
        debugName: 'venera-js-worker-$id',
        errorsAreFatal: true,
      );
      unawaited(
        Future<void>.delayed(readyTimeout).then((_) {
          if (!_readyCompleter.isCompleted) {
            _markFailed(
              TimeoutException(
                'JS worker $id did not become ready within $readyTimeout',
              ),
            );
          }
        }),
      );
    } catch (e, s) {
      _markFailed(e, s);
    }
  }

  void _onMessage(dynamic message) {
    if (_isClosed) return;
    if (message is _WorkerReady) {
      _sendPort = message.sendPort;
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
      return;
    }
    if (message is TaskResult) {
      final completer = _tasks.remove(message.id);
      final timer = _taskTimers.remove(message.id);
      timer?.cancel();
      if (completer == null || completer.isCompleted) return;
      if (message.error != null) {
        completer.completeError(StateError(message.error!));
      } else {
        completer.complete(message.result);
      }
      return;
    }
    if (message is WorkerFailure) {
      _markFailed(
        StateError(message.message),
        StackTrace.fromString(message.stackTrace ?? ''),
      );
      return;
    }
    AppDiagnostics.warn('js.pool', 'unknown_worker_message', data: {'message': '$message'});
  }

  Future<dynamic> execute(
    String jsFunction,
    List<dynamic> args, {
    required Duration timeout,
    String? sourceKey,
  }) async {
    if (_isClosed) {
      throw StateError('IsolateJsEngine $id is closed');
    }
    if (_isFailed) {
      throw StateError('IsolateJsEngine $id has failed');
    }
    await ready;
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('IsolateJsEngine $id is not ready');
    }

    final taskId = _counter++;
    final completer = Completer<dynamic>();
    _tasks[taskId] = completer;
    _taskTimers[taskId] = Timer(timeout, () {
      final pending = _tasks.remove(taskId);
      _taskTimers.remove(taskId);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          TimeoutException('JS task $taskId timed out after $timeout'),
        );
      }
    });

    try {
      sendPort.send(Task(taskId, jsFunction, args, sourceKey: sourceKey));
    } catch (e, s) {
      _tasks.remove(taskId);
      _taskTimers.remove(taskId)?.cancel();
      completer.completeError(e, s);
    }
    return completer.future;
  }

  Future<void> close({bool force = false}) async {
    if (_isClosed) return;
    _isClosed = true;
    if (force) {
      _completeAllPending(StateError('JS worker $id was closed'));
    } else {
      await _waitForTasksToDrain(timeout: const Duration(seconds: 3));
      _completeAllPending(
        StateError('JS worker $id was closed before completion'),
      );
    }

    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  Future<void> _waitForTasksToDrain({required Duration timeout}) async {
    if (_tasks.isEmpty) return;
    try {
      await Future.any([
        Future.wait(_tasks.values.map((c) => c.future), eagerError: false),
        Future<void>.delayed(timeout),
      ]);
    } catch (_) {
      // Best effort only.
    }
  }

  void _markFailed(Object error, [StackTrace? stackTrace]) {
    _isFailed = true;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, stackTrace);
    }
    _failAll(error, stackTrace);
    unawaited(close(force: true));
  }

  void _failAll(Object error, [StackTrace? stackTrace]) {
    AppDiagnostics.error(
      'js.pool',
      error,
      stackTrace: stackTrace,
      message: 'worker_failed',
      data: {'workerId': id},
    );
    _completeAllPending(error, stackTrace);
  }

  void _completeAllPending(Object error, [StackTrace? stackTrace]) {
    for (final timer in _taskTimers.values) {
      timer.cancel();
    }
    _taskTimers.clear();
    for (final completer in _tasks.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    _tasks.clear();
  }

  static Future<void> _run(_IsolateJsEngineInitParam params) async {
    final parentSendPort = params.sendPort;
    final workerReceivePort = ReceivePort();
    parentSendPort.send(_WorkerReady(workerReceivePort.sendPort));

    final engine = JsComputeEngine();
    try {
      await engine.init(params.jsInit);
    } catch (e, s) {
      parentSendPort.send(
        WorkerFailure('Failed to initialize JS engine: $e', s.toString()),
      );
      workerReceivePort.close();
      return;
    }

    await for (final message in workerReceivePort) {
      if (message is! Task) continue;
      JSInvokable? jsFunc;
      try {
        final evaluated = engine.runCode(
          message.jsFunction,
          '<pool-task-${message.id}>',
        );
        if (evaluated is! JSInvokable) {
          throw StateError('The provided code does not evaluate to a function');
        }
        jsFunc = evaluated;
        final result = jsFunc.invoke(message.args);
        final sanitized = _sanitizeSendable(result);
        parentSendPort.send(TaskResult.success(message.id, sanitized));
      } catch (e, s) {
        parentSendPort.send(TaskResult.failure(message.id, '$e', s.toString()));
      } finally {
        try {
          jsFunc?.free();
        } catch (_) {
          // Ignore cleanup failure.
        }
      }
    }
    engine.dispose();
  }

  static Object? _sanitizeSendable(dynamic value) {
    if (value == null || value is bool || value is num || value is String) {
      return value;
    }
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is List) {
      return value.map<Object?>(_sanitizeSendable).toList(growable: false);
    }
    if (value is Map) {
      final mapped = <String, Object?>{};
      value.forEach((key, item) {
        mapped[key.toString()] = _sanitizeSendable(item);
      });
      return mapped;
    }
    throw UnsupportedError(
      'Unsupported non-sendable JS result type: ${value.runtimeType}',
    );
  }
}

class _WorkerReady {
  final SendPort sendPort;

  const _WorkerReady(this.sendPort);
}

class WorkerFailure {
  final String message;
  final String? stackTrace;

  const WorkerFailure(this.message, [this.stackTrace]);
}

class Task {
  final int id;
  final String jsFunction;
  final List<dynamic> args;
  final String? sourceKey;

  const Task(this.id, this.jsFunction, this.args, {this.sourceKey});
}

class TaskResult {
  final int id;
  final Object? result;
  final String? error;
  final String? stackTrace;

  const TaskResult._({
    required this.id,
    required this.result,
    required this.error,
    required this.stackTrace,
  });

  factory TaskResult.success(int id, Object? result) {
    return TaskResult._(id: id, result: result, error: null, stackTrace: null);
  }

  factory TaskResult.failure(int id, String error, [String? stackTrace]) {
    return TaskResult._(
      id: id,
      result: null,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
