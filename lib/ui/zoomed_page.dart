import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double minPageZoom = 0.2;
const double maxPageZoom = 2.0;
const double pageZoomStep = 0.1;

double clampPageZoom(double value) {
  return value.clamp(minPageZoom, maxPageZoom).toDouble();
}

String pageZoomLabel(double value) {
  return '${(clampPageZoom(value) * 100).round()}%';
}

double stepPageZoom(double value, int steps) {
  return clampPageZoom(value + (steps * pageZoomStep));
}

final class ZoomedPage extends StatelessWidget {
  const ZoomedPage({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effectiveScale = clampPageZoom(scale);
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: child,
    );
  }
}

final class ZoomInteractionSurface extends StatefulWidget {
  const ZoomInteractionSurface({
    super.key,
    required this.scale,
    required this.onScaleChanged,
    required this.child,
  });

  final double scale;
  final ValueChanged<double> onScaleChanged;
  final Widget child;

  @override
  State<ZoomInteractionSurface> createState() => _ZoomInteractionSurfaceState();
}

final class _ZoomInteractionSurfaceState extends State<ZoomInteractionSurface> {
  final Map<int, Offset> _touches = <int, Offset>{};
  double? _pinchStartDistance;
  double _pinchStartScale = 1;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _trackPointerDown,
      onPointerMove: _trackPointerMove,
      onPointerUp: _trackPointerEnd,
      onPointerCancel: _trackPointerEnd,
      onPointerSignal: _handlePointerSignal,
      child: widget.child,
    );
  }

  void _trackPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }

    _touches[event.pointer] = event.position;
    if (_touches.length == 2) {
      _pinchStartDistance = _currentTouchDistance();
      _pinchStartScale = widget.scale;
    }
  }

  void _trackPointerMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }

    _touches[event.pointer] = event.position;
    if (_touches.length < 2) {
      return;
    }

    final startDistance = _pinchStartDistance ?? _currentTouchDistance();
    final currentDistance = _currentTouchDistance();
    if (startDistance == null ||
        currentDistance == null ||
        startDistance <= 0) {
      return;
    }

    _pinchStartDistance ??= startDistance;
    widget.onScaleChanged(
      clampPageZoom(_pinchStartScale * currentDistance / startDistance),
    );
  }

  void _trackPointerEnd(PointerEvent event) {
    _touches.remove(event.pointer);
    if (_touches.length < 2) {
      _pinchStartDistance = null;
      _pinchStartScale = widget.scale;
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }

    final steps = event.scrollDelta.dy < 0 ? 1 : -1;
    widget.onScaleChanged(stepPageZoom(widget.scale, steps));
  }

  double? _currentTouchDistance() {
    if (_touches.length < 2) {
      return null;
    }

    final points = _touches.values.take(2).toList(growable: false);
    final dx = points[0].dx - points[1].dx;
    final dy = points[0].dy - points[1].dy;
    return math.sqrt((dx * dx) + (dy * dy));
  }
}
