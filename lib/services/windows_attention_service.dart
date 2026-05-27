import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class WindowsAttentionService {
  const WindowsAttentionService();

  bool get isSupported => Platform.isWindows;

  bool flashTaskbar({int count = 8}) {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      final hwnd = _findCurrentProcessWindow();
      if (hwnd == 0) {
        return false;
      }

      final info = calloc<_FlashInfo>();
      try {
        info.ref.cbSize = sizeOf<_FlashInfo>();
        info.ref.hwnd = hwnd;
        info.ref.dwFlags = _flashAll;
        info.ref.uCount = count;
        info.ref.dwTimeout = 0;
        return _flashWindowEx(info) != 0;
      } finally {
        calloc.free(info);
      }
    } catch (_) {
      return false;
    }
  }

  bool playAlarmFallback() {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      final didMessageBeep = _messageBeep(_mbIconExclamation) != 0;
      final didHighBeep = _beep(880, 260) != 0;
      final didLowBeep = _beep(660, 260) != 0;
      return didMessageBeep || didHighBeep || didLowBeep;
    } catch (_) {
      return false;
    }
  }
}

const int _flashCaption = 0x00000001;
const int _flashTray = 0x00000002;
const int _flashAll = _flashCaption | _flashTray;
const int _mbIconExclamation = 0x00000030;

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function() _getCurrentProcessId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');

final int Function() _getActiveWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow');

final int Function(int type) _messageBeep = _user32
    .lookupFunction<Int32 Function(Uint32 type), int Function(int type)>(
      'MessageBeep',
    );

final int Function(int frequency, int duration) _beep = _kernel32
    .lookupFunction<
      Int32 Function(Uint32 frequency, Uint32 duration),
      int Function(int frequency, int duration)
    >('Beep');

final int Function(int hwnd, Pointer<Uint32> processId)
_getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr hwnd, Pointer<Uint32> processId),
      int Function(int hwnd, Pointer<Uint32> processId)
    >('GetWindowThreadProcessId');

final int Function(int hwnd) _isWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr hwnd), int Function(int hwnd)>(
      'IsWindowVisible',
    );

final int Function(Pointer<_FlashInfo> info) _flashWindowEx = _user32
    .lookupFunction<
      Int32 Function(Pointer<_FlashInfo> info),
      int Function(Pointer<_FlashInfo> info)
    >('FlashWindowEx');

final int Function(
  Pointer<NativeFunction<_EnumWindowsProcNative>> proc,
  int lParam,
)
_enumWindows = _user32
    .lookupFunction<
      Int32 Function(
        Pointer<NativeFunction<_EnumWindowsProcNative>> proc,
        IntPtr lParam,
      ),
      int Function(
        Pointer<NativeFunction<_EnumWindowsProcNative>> proc,
        int lParam,
      )
    >('EnumWindows');

final Pointer<NativeFunction<_EnumWindowsProcNative>> _enumWindowsProc =
    Pointer.fromFunction<_EnumWindowsProcNative>(_enumWindowsCallback, 1);

int _enumTargetPid = 0;
int _enumFoundWindow = 0;

int _findCurrentProcessWindow() {
  final processId = _getCurrentProcessId();
  final active = _getActiveWindow();
  if (_isCurrentProcessWindow(active, processId)) {
    return active;
  }

  _enumTargetPid = processId;
  _enumFoundWindow = 0;
  _enumWindows(_enumWindowsProc, 0);
  final found = _enumFoundWindow;
  _enumTargetPid = 0;
  _enumFoundWindow = 0;
  return found;
}

bool _isCurrentProcessWindow(int hwnd, int processId) {
  if (hwnd == 0 || _isWindowVisible(hwnd) == 0) {
    return false;
  }

  final pid = calloc<Uint32>();
  try {
    _getWindowThreadProcessId(hwnd, pid);
    return pid.value == processId;
  } finally {
    calloc.free(pid);
  }
}

int _enumWindowsCallback(int hwnd, int lParam) {
  if (_isCurrentProcessWindow(hwnd, _enumTargetPid)) {
    _enumFoundWindow = hwnd;
    return 0;
  }
  return 1;
}

typedef _EnumWindowsProcNative = Int32 Function(IntPtr hwnd, IntPtr lParam);

final class _FlashInfo extends Struct {
  @Uint32()
  external int cbSize;

  @IntPtr()
  external int hwnd;

  @Uint32()
  external int dwFlags;

  @Uint32()
  external int uCount;

  @Uint32()
  external int dwTimeout;
}
