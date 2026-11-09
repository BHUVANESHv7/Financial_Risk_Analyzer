import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Semicircle gauge for a 0–100 risk score. Animates smoothly between values,
/// which makes live recalculation feel immediate.
class RiskGauge extends StatelessWidget {
  final double score;
  final double size;
  final String? caption;
  final bool busy;

  const RiskGauge({
    super.key,
    required this.score,
    this.size = 200,
    this.caption,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: score.clamp(0, 100).toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final color = Color.lerp(
          Color.lerp(p.success, p.warning, (value / 50).clamp(0, 1))!,
          p.danger,
          ((value - 50) / 50).clamp(0, 1),
        )!;
        return SizedBox(
          width: size,
          height: size * 0.62,
          child: CustomPaint(
            painter: _GaugePainter(value, color, p.border),
            child: Align(
              alignment: const Alignment(0, 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedOpacity(
                    opacity: busy ? 0.45 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      value.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: size * 0.2,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(caption ?? 'risk score',
                      style: TextStyle(fontSize: 12, color: p.muted, letterSpacing: 0.4)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color, track;
  _GaugePainter(this.value, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.width / 2),
      radius: size.width / 2 - stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    canvas.drawArc(rect, pi, pi, false, base..color = track);
    if (value > 0.5) {
      canvas.drawArc(rect, pi, pi * (value / 100), false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}
