import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A right or left handed quarter-circle volume control.
class ArcVolumeSlider extends StatelessWidget {
  const ArcVolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.leftHanded,
    this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;
  final bool leftHanded;

  static const double size = 300;
  static const Offset center = Offset(258, 258);
  static const double radius = 207;

  void _update(Offset point) {
    final x = leftHanded ? size - point.dx : point.dx;
    final rawAngle = math.atan2(point.dy - center.dy, x - center.dx);
    final angle = rawAngle < 0 ? rawAngle + 2 * math.pi : rawAngle;
    // On screen this quarter arc runs from lower-left (zero) to upper-right.
    final normalized = ((angle - math.pi) / (math.pi / 2)).clamp(0.0, 1.0);
    onChanged(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Volume',
      value: '${(value * 100).round()} percent',
      increasedValue:
          '${((value + .05).clamp(0.0, 1.0) * 100).round()} percent',
      decreasedValue:
          '${((value - .05).clamp(0.0, 1.0) * 100).round()} percent',
      onIncrease: () => onChanged((value + .05).clamp(0.0, 1.0)),
      onDecrease: () => onChanged((value - .05).clamp(0.0, 1.0)),
      child: SizedBox.square(
        dimension: size,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) => _update(details.localPosition),
          onPanStart: (details) => _update(details.localPosition),
          onPanUpdate: (details) => _update(details.localPosition),
          onPanEnd: (_) => onChangeEnd?.call(),
          child: CustomPaint(
            painter: _ArcPainter(
              value: value,
              leftHanded: leftHanded,
              accent: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.value,
    required this.leftHanded,
    required this.accent,
  });

  final double value;
  final bool leftHanded;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (leftHanded) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final bounds = Rect.fromCircle(
      center: ArcVolumeSlider.center,
      radius: ArcVolumeSlider.radius,
    );
    final base = Paint()
      ..color = const Color(0xFF46505F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(bounds, math.pi, math.pi / 2, false, base);
    canvas.drawArc(bounds, math.pi, value * math.pi / 2, false, active);
    final angle = math.pi + value * math.pi / 2;
    final thumb = Offset(
      ArcVolumeSlider.center.dx + ArcVolumeSlider.radius * math.cos(angle),
      ArcVolumeSlider.center.dy + ArcVolumeSlider.radius * math.sin(angle),
    );
    canvas.drawCircle(thumb, 14, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      value != oldDelegate.value ||
      leftHanded != oldDelegate.leftHanded ||
      accent != oldDelegate.accent;
}
