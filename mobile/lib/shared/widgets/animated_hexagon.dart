/// Animated hexagon mascot widget — the MyLoop equivalent of Duolingo's bird.
///
/// A pulsing, rotating hexagon with gradient fills that serves as the app's
/// character/mascot. Used in loading states, celebrations, and empty states.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';

/// An animated hexagon that pulses and gently bobs up and down.
class AnimatedHexagon extends StatefulWidget {
  final double size;
  final bool celebrate; // burst animation for achievements
  final Color? color;

  const AnimatedHexagon({
    super.key,
    this.size = 80,
    this.celebrate = false,
    this.color,
  });

  @override
  State<AnimatedHexagon> createState() => _AnimatedHexagonState();
}

class _AnimatedHexagonState extends State<AnimatedHexagon>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _bobController;
  late final AnimationController _rotateController;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _bobAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bobAnim = Tween<double>(begin: -4, end: 4).animate(
      CurvedAnimation(parent: _bobController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bobController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _bobAnim, _rotateController]),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bobAnim.value),
          child: Transform.scale(
            scale: _pulseAnim.value,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _HexagonPainter(
                  rotation: _rotateController.value * 2 * math.pi * 0.05,
                  color: widget.color ?? AppColors.primary,
                  celebrate: widget.celebrate,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter for a hexagon with gradient fill and glow.
class _HexagonPainter extends CustomPainter {
  final double rotation;
  final Color color;
  final bool celebrate;

  _HexagonPainter({
    required this.rotation,
    required this.color,
    required this.celebrate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final path = _hexPath(radius);

    // Glow shadow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(path, glowPaint);

    // Gradient fill
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        color,
        Color.lerp(color, Colors.white, 0.3)!,
        color,
      ],
    );
    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawPath(path, fillPaint);

    // Border highlight
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, borderPaint);

    // Inner hex (smaller, darker)
    final innerPath = _hexPath(radius * 0.6);
    final innerPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(innerPath, innerPaint);

    // Face — two eyes and a smile
    final facePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Eyes
    canvas.drawCircle(Offset(-radius * 0.2, -radius * 0.1), radius * 0.08, facePaint);
    canvas.drawCircle(Offset(radius * 0.2, -radius * 0.1), radius * 0.08, facePaint);

    // Pupils
    final pupilPaint = Paint()..color = color.withValues(alpha: 0.8);
    canvas.drawCircle(Offset(-radius * 0.2, -radius * 0.08), radius * 0.04, pupilPaint);
    canvas.drawCircle(Offset(radius * 0.2, -radius * 0.08), radius * 0.04, pupilPaint);

    // Smile
    final smilePath = Path()
      ..moveTo(-radius * 0.15, radius * 0.12)
      ..quadraticBezierTo(0, radius * 0.28, radius * 0.15, radius * 0.12);
    final smilePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(smilePath, smilePaint);

    // Celebration sparkles
    if (celebrate) {
      final sparklePaint = Paint()..color = AppColors.yellow;
      for (int i = 0; i < 6; i++) {
        final angle = (i * math.pi / 3) + rotation * 5;
        final sparkleR = radius * 1.3;
        canvas.drawCircle(
          Offset(math.cos(angle) * sparkleR, math.sin(angle) * sparkleR),
          3, sparklePaint,
        );
      }
    }

    canvas.restore();
  }

  Path _hexPath(double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final x = r * math.cos(angle);
      final y = r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HexagonPainter oldDelegate) =>
      rotation != oldDelegate.rotation || celebrate != oldDelegate.celebrate;
}
