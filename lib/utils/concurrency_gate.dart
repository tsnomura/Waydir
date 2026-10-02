import 'dart:async';

class ConcurrencyGate {
  int _available;
  final _waitQueue = <Completer<void>>[];

  ConcurrencyGate(int permits) : _available = permits;

  Future<void> acquire() {
    if (_available > 0) {
      _available--;

      return Future.value();
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);

    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    } else {
      _available++;
    }
  }
}
