/// Splash screen — hex rush animation shown when the app opens.
///
/// Multiple hex trophies of all tiers fly in from outside the screen,
/// settle into a hex grid pattern, then fade out to reveal the app.
/// Inspired by Duolingo's opening animation.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:myloop/shared/widgets/hex_trophy.dart';

/// Splash screen that plays the hex rush animation then calls [onComplete].
class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _flyController;
  late final AnimationController _pulseController;
  late final AnimationController _exitController;
  late final Animation<double> _flyAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _exitAnim;

  final _rng = math.Random(42);

  // 18 hex particles: position, tier, delay, trajectory
  late final List<_HexParticle> _particles;

  @override
  void initState() {
    super.initState();

    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _flyAnim = CurvedAnimation(parent: _flyController, curve: Curves.easeOutBack);
    _pulseAnim = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _exitAnim = CurvedAnimation(parent: _exitController, curve: Curves.easeIn);

    _particles = List.generate(18, (i) {
      final tier = HexTier.values[i % HexTier.values.length];
      final startAngle = _rng.nextDouble() * math.pi * 2;
      final startDist = 1.8 + _rng.nextDouble() * 0.4;
      return _HexParticle(
        tier: tier,
        startFraction: Offset(
          0.5 + math.cos(startAngle) * startDist,
          0.5 + math.sin(startAngle) * startDist,
        ),
        endFraction: Offset(
          0.15 + (i % 6) * 0.14,
          0.35 + (i ~/ 6) * 0.14,
        ),
        delay: i * 0.04,
        size: 42.0 + _rng.nextDouble() * 16,
        rotationDir: _rng.nextBool() ? 1.0 : -1.0,
      );
    });

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _flyController.forward();
    await Future.delayed(const Duration(milliseconds: 1000));
    _pulseController.forward();
    await Future.delayed(const Duration(milliseconds: 700));
    _exitController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    widget.onComplete();
  }

  @override
  void dispose() {
    _flyController.dispose();
    _pulseController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628), // deep navy
      body: AnimatedBuilder(
        animation: Listenable.merge([_flyAnim, _pulseAnim, _exitAnim]),
        builder: (context, child) {
          final exitOpacity = (1.0 - _exitAnim.value).clamp(0.0, 1.0);

          return Opacity(
            opacity: exitOpacity,
            child: Stack(
              children: [
                // Background subtle hex grid pattern
                CustomPaint(
                  size: size,
                  painter: _HexGridPainter(progress: _flyAnim.value),
                ),

                // Animated hex particles
                ..._particles.map((p) {
                  final t = ((_flyAnim.value - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
                  final pos = Offset.lerp(
                    Offset(size.width * p.startFraction.dx, size.height * p.startFraction.dy),
                    Offset(size.width * p.endFraction.dx, size.height * p.endFraction.dy),
                    t,
                  )!;
                  final opacity = t.clamp(0.0, 1.0);
                  final pulse = 1.0 + (_pulseAnim.value * 0.15 * math.sin(_pulseAnim.value * math.pi));
                  final rotation = p.rotationDir * (1.0 - t) * math.pi;

                  return Positioned(
                    left: pos.dx - p.size / 2,
                    top: pos.dy - p.size / 2,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.rotate(
                        angle: rotation,
                        child: Transform.scale(
                          scale: (0.5 + t * 0.5) * pulse,
                          child: SizedBox(
                            width: p.size,
                            height: p.size,
                            child: CustomPaint(painter: _SplashHexPainter(tier: p.tier)),
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                // Center logo
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 40), // shift slightly up
                      Transform.scale(
                        scale: 0.8 + _flyAnim.value * 0.2 + _pulseAnim.value * 0.08,
                        child: Opacity(
                          opacity: _flyAnim.value.clamp(0.0, 1.0),
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: CustomPaint(painter: _SplashHexPainter(tier: HexTier.crystal)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Opacity(
                        opacity: _flyAnim.value.clamp(0.0, 1.0),
                        child: const Text(
                          'MyLoop',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: (_flyAnim.value - 0.3).clamp(0.0, 1.0),
                        child: Text(
                          'Walk. Capture. Conquer.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Data for a single flying hex particle.
class _HexParticle {
  final HexTier tier;
  final Offset startFraction;
  final Offset endFraction;
  final double delay; // 0.0–0.5
  final double size;
  final double rotationDir;

  const _HexParticle({
    required this.tier,
    required this.startFraction,
    required this.endFraction,
    required this.delay,
    required this.size,
    required this.rotationDir,
  });
}

/// Paints a tier-colored hexagon (simplified for splash performance).
class _SplashHexPainter extends CustomPainter {
  final HexTier tier;
  _SplashHexPainter({required this.tier});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.45;
    canvas.save();
    canvas.translate(center.dx, center.dy);

    final path = _hexPath(radius);

    // Glow
    canvas.drawPath(path, Paint()
      ..color = tier.glow.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    // Fill
    canvas.drawPath(path, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tier.color, tier.colorSecondary],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));

    // Border
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.4));

    canvas.restore();
  }

  Path _hexPath(double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      if (i == 0) {
        path.moveTo(r * math.cos(angle), r * math.sin(angle));
      } else {
        path.lineTo(r * math.cos(angle), r * math.sin(angle));
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _SplashHexPainter old) => tier != old.tier;
}

/// Paints faint hex outlines as a background grid pattern.
class _HexGridPainter extends CustomPainter {
  final double progress;
  _HexGridPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const hexR = 30.0;
    const w = hexR * 2;
    const h = hexR * 1.732;

    for (double y = -hexR; y < size.height + hexR; y += h) {
      for (double x = -hexR; x < size.width + hexR; x += w * 1.5) {
        final offset = (y / h).floor().isOdd ? hexR * 0.75 : 0.0;
        canvas.save();
        canvas.translate(x + offset, y);
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = (math.pi / 3) * i - math.pi / 2;
          if (i == 0) {
            path.moveTo(hexR * math.cos(angle), hexR * math.sin(angle));
          } else {
            path.lineTo(hexR * math.cos(angle), hexR * math.sin(angle));
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HexGridPainter old) => progress != old.progress;
}
