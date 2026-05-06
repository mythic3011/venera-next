import 'dart:async';
import 'dart:collection';

class Channel<T> {
  final Queue<T> _queue;

  final int size;

  Channel(this.size) : _queue = Queue<T>();

  final Queue<Completer<void>> _releaseWaiters = Queue<Completer<void>>();

  Completer? _pushCompleter;

  var currentSize = 0;

  var _reservedSlots = 0;

  var isClosed = false;

  Future<void> push(T item) async {
    while (currentSize + _reservedSlots >= size) {
      if (isClosed) {
        return;
      }
      var waiter = Completer<void>();
      _releaseWaiters.addLast(waiter);
      await waiter.future;
      if (isClosed) {
        return;
      }
      _reservedSlots--;
      break;
    }
    _queue.addLast(item);
    currentSize++;
    _pushCompleter?.complete();
    _pushCompleter = null;
  }

  Future<T?> pop() async {
    while (_queue.isEmpty) {
      if (isClosed) {
        return null;
      }
      _pushCompleter ??= Completer();
      await _pushCompleter!.future;
    }
    var item = _queue.removeFirst();
    currentSize--;
    _wakeNextPusher();
    return item;
  }

  void close() {
    isClosed = true;
    _pushCompleter?.complete();
    while (_releaseWaiters.isNotEmpty) {
      _releaseWaiters.removeFirst().complete();
    }
  }

  void _wakeNextPusher() {
    // Reserve one freed slot per waiter so competing producers cannot overfill
    // the bounded channel before the woken producer resumes.
    while (_releaseWaiters.isNotEmpty && currentSize + _reservedSlots < size) {
      _reservedSlots++;
      _releaseWaiters.removeFirst().complete();
    }
  }
}
