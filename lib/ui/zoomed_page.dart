import 'package:flutter/material.dart';

const double minPageZoom = 0.2;
const double maxPageZoom = 2.0;

double clampPageZoom(double value) {
  return value.clamp(minPageZoom, maxPageZoom).toDouble();
}

String pageZoomLabel(double value) {
  return '${(clampPageZoom(value) * 100).round()}%';
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
