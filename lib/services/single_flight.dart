/// Share only simultaneous reads. Results and failures are never cached.
class SingleFlight {
  final Map<String, Future<dynamic>> _running = {};
  Future<T> run<T>(String key, Future<T> Function() work) async {
    final existing = _running[key];
    if (existing != null) return await existing as T;
    if (_running.length >= 128) return work();
    final task = Future<T>.sync(work);
    _running[key] = task;
    try {
      return await task;
    } finally {
      if (identical(_running[key], task)) _running.remove(key);
    }
  }
}
