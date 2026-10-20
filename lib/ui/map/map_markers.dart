import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Anchor symbol in a ring. Large enough to grab with a wet finger.
class AnchorMarkerIcon extends StatelessWidget {
  const AnchorMarkerIcon({super.key, this.dragging = false, this.draft = false});

  static const size = 56.0;
  final bool dragging;
  final bool draft;

  @override
  Widget build(BuildContext context) {
    final c = AnchorColors.of(context);
    final color = draft ? c.neutral : c.anchor;
    return Semantics(
      label: 'Anchor',
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: dragging ? 48 : 38,
          height: dragging ? 48 : 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.night ? Colors.black : Colors.white.withValues(alpha: 0.9),
            border: Border.all(color: color, width: 2.5),
          ),
          child: Icon(Icons.anchor, color: color, size: dragging ? 30 : 24),
        ),
      ),
    );
  }
}

/// Boat symbol: an arrow pointing along [headingDeg], or a dot without heading.
class BoatMarkerIcon extends StatelessWidget {
  const BoatMarkerIcon({super.key, this.headingDeg});

  static const size = 44.0;
  final double? headingDeg;

  @override
  Widget build(BuildContext context) {
    final c = AnchorColors.of(context);
    final h = headingDeg;
    return Semantics(
      label: 'Boat',
      child: h == null
          ? Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.boat,
                  border: Border.all(
                    color: c.night ? Colors.black : Colors.white,
                    width: 3,
                  ),
                ),
              ),
            )
          : Transform.rotate(
              angle: h * math.pi / 180,
              child: CustomPaint(
                size: const Size.square(size),
                painter: _BoatPainter(
                  fill: c.boat,
                  outline: c.night ? Colors.black : Colors.white,
                ),
              ),
            ),
    );
  }
}

class _BoatPainter extends CustomPainter {
  _BoatPainter({required this.fill, required this.outline});
  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Simple hull pointing up (bow at top).
    final path = Path()
      ..moveTo(w / 2, h * 0.08)
      ..quadraticBezierTo(w * 0.78, h * 0.35, w * 0.70, h * 0.88)
      ..lineTo(w * 0.30, h * 0.88)
      ..quadraticBezierTo(w * 0.22, h * 0.35, w / 2, h * 0.08)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_BoatPainter old) => old.fill != fill || old.outline != outline;
}
