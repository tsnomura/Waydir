class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();

      return;
    }
    _listeners.add(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

class SharedJob<T> {
  final abort = CancelToken();
  late final Future<T> future;
  int _waiters = 0;
  bool _pinned = false;
  bool _done = false;

  SharedJob(Future<T> Function(CancelToken abort) run) {
    future = run(abort).whenComplete(() => _done = true);
  }

  bool get isAborted => abort.isCancelled;

  void join(CancelToken? caller) {
    if (caller == null) {
      _pinned = true;

      return;
    }
    _waiters++;
    caller.onCancel(() {
      if (_done) return;
      _waiters--;
      if (_waiters == 0 && !_pinned) abort.cancel();
    });
  }
}

class SharedJobs<T> {
  final _jobs = <String, SharedJob<T>>{};

  Future<T> run(
    String key,
    CancelToken? caller,
    Future<T> Function(CancelToken abort) start,
  ) {
    final existing = _jobs[key];
    if (existing != null && existing.isAborted) {
      return existing.future.then(
        (_) => run(key, caller, start),
        onError: (_) => run(key, caller, start),
      );
    }
    final job =
        existing ??
        (_jobs[key] = SharedJob<T>(
          (abort) => Future.sync(
            () => start(abort),
          ).whenComplete(() => _jobs.remove(key)),
        ));
    job.join(caller);

    return job.future;
  }
}
