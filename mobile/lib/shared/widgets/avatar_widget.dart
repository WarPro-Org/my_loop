/// Avatar widget and emoji definitions for player identity display.
///
/// Provides the [AvatarWidget] which renders a player's emoji on top of
/// a plain colored circle background.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:myloop/shared/widgets/hex_trophy.dart';

/// The ordered list of emoji characters available as player avatars.
const avatarEmojis = [
  '🦊', // 0 - fox
  '🐸', // 1 - frog
  '🦉', // 2 - owl
  '🐯', // 3 - tiger
  '🐼', // 4 - panda
  '🦁', // 5 - lion
  '🐨', // 6 - koala
  '🐙', // 7 - octopus
  '🦄', // 8 - unicorn
  '🐲', // 9 - dragon
  '🦈', // 10 - shark
  '🦅', // 11 - eagle
];

/// Displays a player's avatar emoji on a plain colored circle background.
///
/// Uses the player's chosen color as background. Simple and clean.
class AvatarWidget extends StatelessWidget {
  final int avatarId;
  final String color;
  final double size;
  final int hexes; // kept for API compat, not used visually
  final bool showBackground;

  const AvatarWidget({
    super.key,
    required this.avatarId,
    required this.color,
    this.size = 48,
    this.hexes = 0,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final emoji = avatarEmojis[avatarId.clamp(0, avatarEmojis.length - 1)];
    final bgColor = Color(int.parse(color.replaceFirst('#', ''), radix: 16) | 0xFF000000);

    if (!showBackground) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size * 0.55)),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor.withValues(alpha: 0.2),
        border: Border.all(color: bgColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: TextStyle(fontSize: size * 0.45),
      ),
    );
  }
}

/// Paints a vibrant hex badge with tier colors, division indicator, and glow.
/// Used as avatar background — shows the player's rank badge at a glance.
class AvatarHexBadgePainter extends CustomPainter {
  final HexTier tier;
  final int division;
  AvatarHexBadgePainter({required this.tier, required this.division});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;
    canvas.save();
    canvas.translate(center.dx, center.dy);

    final path = _hexPath(radius);

    // Strong outer glow (scales with tier)
    canvas.drawPath(path, Paint()
      ..color = tier.color.withValues(alpha: 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10.0 + tier.level * 3));

    // Second glow layer (tier glow color)
    canvas.drawPath(path, Paint()
      ..color = tier.glow.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));

    // Vibrant gradient fill
    canvas.drawPath(path, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tier.glow, tier.color, tier.colorSecondary, tier.color],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));

    // Metallic border
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.8),
          tier.colorSecondary,
          Colors.white.withValues(alpha: 0.3),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));

    // Division inner badge (scales up with division)
    final innerScale = 0.18 + (division - 1) * 0.06;
    final innerPath = _hexPath(radius * innerScale);
    canvas.drawPath(innerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.12 + division * 0.04));
    canvas.drawPath(innerPath, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 + division * 0.2
      ..color = Colors.white.withValues(alpha: 0.3 + division * 0.1));

    // Division 3+: chevron
    if (division >= 3) {
      final chevY = -radius * 0.6;
      canvas.drawPath(
        Path()
          ..moveTo(-radius * 0.12, chevY + 3)
          ..lineTo(0, chevY)
          ..lineTo(radius * 0.12, chevY + 3),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Division 4: wings
    if (division >= 4) {
      canvas.drawPath(
        Path()
          ..moveTo(-radius * 0.5, 0)
          ..quadraticBezierTo(-radius * 0.38, -radius * 0.18, -radius * 0.22, -radius * 0.08),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        Path()
          ..moveTo(radius * 0.5, 0)
          ..quadraticBezierTo(radius * 0.38, -radius * 0.18, radius * 0.22, -radius * 0.08),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Top shine highlight
    canvas.drawPath(
      Path()
        ..moveTo(-radius * 0.2, -radius * 0.42)
        ..quadraticBezierTo(0, -radius * 0.52, radius * 0.12, -radius * 0.38),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

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
  bool shouldRepaint(covariant AvatarHexBadgePainter old) =>
      tier != old.tier || division != old.division;
}

