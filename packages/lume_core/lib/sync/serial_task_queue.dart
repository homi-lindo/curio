/// Runs async tasks strictly one at a time, in submission order.
///
/// The sync servers use this to make their state invariant explicit: the
/// read→merge→save section of `/sync` must never interleave, or one request's
/// merge silently overwrites the other's. Errors stay with their own caller —
/// a failing task never breaks the chain for the tasks queued after it.
final class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
