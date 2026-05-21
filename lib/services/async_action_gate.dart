final class AsyncActionGate {
  bool _running = false;

  bool get isRunning => _running;

  bool tryEnter() {
    if (_running) {
      return false;
    }
    _running = true;
    return true;
  }

  void leave() {
    _running = false;
  }
}
