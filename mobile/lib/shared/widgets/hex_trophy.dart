/// Hex trophy tier system — progressive hex badges from Bronze to Diamond.
///
/// Each tier has 4 divisions (like Rocket League: I, II, III, IV).
/// Each badge animates with a subtle pulse when displayed.
/// Tiers: Bronze → Silver → Gold → Platinum → Crystal → Diamond.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';

/// The 6 hex trophy tiers in ascending order.
enum HexTier {
  bronze(0, 'Bronze', 0),
  silver(1, 'Silver', 50),
  gold(2, 'Gold', 200),
  platinum(3, 'Platinum', 500),
  crystal(4, 'Crystal', 1500),
  diamond(5, 'Diamond', 3000);

  final int level;
  final String label;
  final int threshold;

  const HexTier(this.level, this.label, this.threshold);

  /// Get the tier for a given hex count.
  static HexTier fromHexes(int hexes) {
    if (hexes >= diamond.threshold) return diamond;
    if (hexes >= crystal.threshold) return crystal;
    if (hexes >= platinum.threshold) return platinum;
    if (hexes >= gold.threshold) return gold;
    if (hexes >= silver.threshold) return silver;
    return bronze;
  }

  /// Get the division (1-4) within this tier.
  static int divisionFromHexes(int hexes) {
    final tier = fromHexes(hexes);
    final n = tier.next;
    if (n == null) {
      final inTier = hexes - tier.threshold;
      return ((inTier / 1250).floor()).clamp(0, 3) + 1;
    }
    final range = n.threshold - tier.threshold;
    final inTier = hexes - tier.threshold;
    return ((inTier / (range / 4)).floor()).clamp(0, 3) + 1;
  }

  /// Full label with division: "Bronze II"
  static String fullLabel(int hexes) {
    final tier = fromHexes(hexes);
    final div = divisionFromHexes(hexes);
    const romans = ['I', 'II', 'III', 'IV'];
    return '${tier.label} ${romans[div - 1]}';
  }

  /// Progress within current division (0.0–1.0).
  static double divisionProgress(int hexes) {
    final tier = fromHexes(hexes);
    final div = divisionFromHexes(hexes);
    final n = tier.next;
    final tierRange = n != null ? (n.threshold - tier.threshold).toDouble() : 5000.0;
    final divSize = tierRange / 4;
    final divStart = tier.threshold + (div - 1) * divSize;
    return ((hexes - divStart) / divSize).clamp(0.0, 1.0);
  }

  /// Primary color for this tier.
  Color get color => switch (this) {
    bronze => const Color(0xFFCD7F32),
    silver => const Color(0xFFA8B4C0),
    gold => const Color(0xFFFFD700),
    platinum => const Color(0xFF8B5CF6),
    crystal => const Color(0xFF00BCD4),
    diamond => const Color(0xFF60A5FA),
  };

  /// Secondary/accent color for gradient.
  Color get colorSecondary => switch (this) {
    bronze => const Color(0xFF8B4513),
    silver => const Color(0xFF6B7B8D),
    gold => const Color(0xFFF59E0B),
    platinum => const Color(0xFF6D28D9),
    crystal => const Color(0xFF0097A7),
    diamond => const Color(0xFF2563EB),
  };

  /// Glow/highlight color.
  Color get glow => switch (this) {
    bronze => const Color(0xFFDEB887),
    silver => const Color(0xFFE8EDF2),
    gold => const Color(0xFFFFF176),
    platinum => const Color(0xFFD8B4FE),
    crystal => const Color(0xFF80DEEA),
    diamond => const Color(0xFFBFDBFE),
  };

  /// Next tier (null if already diamond).
  HexTier? get next => level < 5 ? HexTier.values[level + 1] : null;

  /// Progress toward next tier (0.0 - 1.0).
  double progress(int hexes) {
    final nextTier = next;
    if (nextTier == null) return 1.0;
    return ((hexes - threshold) / (nextTier.threshold - threshold)).clamp(0.0, 1.0);
  }
}

/// Animated hex trophy badge — pulses gently wherever displayed.
class HexTrophyBadge extends StatefulWidget {
  final int hexes;
  final double size;
  final bool showLabel;
  final bool showProgress;

  const HexTrophyBadge({
    super.key,
    required this.hexes,
    this.size = 64,
    this.showLabel = true,
    this.showProgress = true,
  });

  @override
  State<HexTrophyBadge> createState() => _HexTrophyBadgeState();
}

class _HexTrophyBadgeState extends State<HexTrophyBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = HexTier.fromHexes(widget.hexes);
    final division = HexTier.divisionFromHexes(widget.hexes);
    const romans = ['I', 'II', 'III', 'IV'];

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final pulse = 1.0 + _ctrl.value * 0.04;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: pulse,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _HexTrophyPainter(
                    tier: tier,
                    division: division,
                    glowPulse: _ctrl.value,
                  ),
                ),
              ),
            ),
            if (widget.showLabel) ...[
              const SizedBox(height: 5),
              Text(
                '${tier.label} ${romans[division - 1]}',
                style: TextStyle(
                  color: tier.color,
                  fontWeight: FontWeight.w800,
                  fontSize: (widget.size * 0.17).clamp(9, 16),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
            if (widget.showProgress) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tier.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tier.color.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hexagon, size: 14, color: tier.color),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.hexes}',
                      style: TextStyle(
                        fontSize: (widget.size * 0.14).clamp(10, 14),
                        color: tier.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 1, height: 12,
                      color: tier.color.withValues(alpha: 0.3),
                    ),
                    Text(
                      romans[division - 1],
                      style: TextStyle(
                        fontSize: (widget.size * 0.13).clamp(9, 13),
                        color: tier.colorSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (tier.next != null) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: widget.size * 1.3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: HexTier.divisionProgress(widget.hexes),
                      minHeight: 4,
                      backgroundColor: tier.color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(tier.color),
                    ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// Paints a tier hexagon with gradients, borders, and division markers.
class _HexTrophyPainter extends CustomPainter {
  final HexTier tier;
  final int division;
  final double glowPulse;

  _HexTrophyPainter({required this.tier, required this.division, this.glowPulse = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.44;

    canvas.save();
    canvas.translate(cx, cy);
    final path = _hexPath(radius);

    // Animated glow
    canvas.drawPath(path, Paint()
      ..color = tier.glow.withValues(alpha: 0.3 + glowPulse * 0.15)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 + tier.level * 2 + glowPulse * 4));

    // Main gradient fill
    canvas.drawPath(path, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tier.color, tier.colorSecondary, tier.color],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));

    // Border
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.7), tier.colorSecondary, Colors.white.withValues(alpha: 0.3)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));

    // Inner hex
    canvas.drawPath(_hexPath(radius * 0.65), Paint()
      ..color = tier.colorSecondary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);

    // Tier details
    _drawTierDetails(canvas, radius);

    // Division indicator (scaled inner badge, chevrons, wings)
    _drawDivisionIndicator(canvas, radius);

    // Shine
    canvas.drawPath(
      Path()
        ..moveTo(-radius * 0.3, -radius * 0.5)
        ..quadraticBezierTo(-radius * 0.1, -radius * 0.6, radius * 0.1, -radius * 0.45),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3 + glowPulse * 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  void _drawDivisionIndicator(Canvas canvas, double radius) {
    // Each division is visually distinct:
    // Div 1: plain hex, minimal decoration
    // Div 2: inner hex + subtle ring
    // Div 3: inner hex + ring + chevron crown
    // Div 4: full detail — inner hex + ring + chevron + wings + center gem

    // Inner hex — scales with division
    final innerR = radius * (0.18 + (division - 1) * 0.07);
    final innerPath = _hexPath(innerR);

    // Division 2+: outer ring
    if (division >= 2) {
      canvas.drawPath(_hexPath(radius * 0.72), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 + (division - 2) * 0.4
        ..color = Colors.white.withValues(alpha: 0.2 + division * 0.08));
    }

    // Inner badge fill (gets more opaque with division)
    canvas.drawPath(innerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.08 + division * 0.06));
    canvas.drawPath(innerPath, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 + division * 0.4
      ..color = Colors.white.withValues(alpha: 0.3 + division * 0.15));

    // Division 3+: chevron crown at top
    if (division >= 3) {
      final chevY = -radius * 0.58;
      // Double chevron for div 4
      for (int c = 0; c < (division >= 4 ? 2 : 1); c++) {
        final offset = c * 5.0;
        canvas.drawPath(
          Path()
            ..moveTo(-radius * 0.18, chevY + 5 + offset)
            ..lineTo(0, chevY + offset)
            ..lineTo(radius * 0.18, chevY + 5 + offset),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55 - c * 0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8 - c * 0.4
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Division 4: wings extending from sides
    if (division >= 4) {
      // Left wing
      canvas.drawPath(
        Path()
          ..moveTo(-radius * 0.6, -radius * 0.05)
          ..quadraticBezierTo(-radius * 0.75, -radius * 0.25, -radius * 0.5, -radius * 0.35)
          ..moveTo(-radius * 0.55, -radius * 0.08)
          ..quadraticBezierTo(-radius * 0.65, -radius * 0.2, -radius * 0.45, -radius * 0.28),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
      // Right wing (mirrored)
      canvas.drawPath(
        Path()
          ..moveTo(radius * 0.6, -radius * 0.05)
          ..quadraticBezierTo(radius * 0.75, -radius * 0.25, radius * 0.5, -radius * 0.35)
          ..moveTo(radius * 0.55, -radius * 0.08)
          ..quadraticBezierTo(radius * 0.65, -radius * 0.2, radius * 0.45, -radius * 0.28),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
      // Center gem
      canvas.drawCircle(Offset(0, radius * 0.45), radius * 0.06, Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }

    // Division number indicator at bottom (Roman numeral dot pattern)
    final dotY = radius * 0.62;
    final dotSpacing = radius * 0.12;
    final startX = -(dotSpacing * (division - 1)) / 2;
    for (int i = 0; i < division; i++) {
      canvas.drawCircle(
        Offset(startX + i * dotSpacing, dotY),
        radius * 0.035,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
    }
  }

  void _drawTierDetails(Canvas canvas, double radius) {
    switch (tier) {
      case HexTier.bronze:
        canvas.drawPath(_hexPath(radius * 0.32), Paint()
          ..color = Colors.white.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 1);
      case HexTier.silver:
        canvas.drawPath(_hexPath(radius * 0.38), Paint()
          ..color = Colors.white.withValues(alpha: 0.35)..style = PaintingStyle.stroke..strokeWidth = 1);
        canvas.drawPath(_hexPath(radius * 0.22), Paint()
          ..color = Colors.white.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 0.8);
      case HexTier.gold:
        _drawStar(canvas, radius * 0.25, Colors.white.withValues(alpha: 0.5));
      case HexTier.platinum:
        for (int i = 0; i < 6; i++) {
          final a = (math.pi / 3) * i - math.pi / 2;
          canvas.drawLine(Offset.zero, Offset(math.cos(a) * radius * 0.5, math.sin(a) * radius * 0.5),
            Paint()..color = Colors.white.withValues(alpha: 0.2)..strokeWidth = 0.7);
        }
      case HexTier.crystal:
        for (int i = 0; i < 3; i++) {
          final a = (math.pi * 2 / 3) * i;
          canvas.drawPath(
            Path()..moveTo(0, 0)
              ..lineTo(math.cos(a - 0.15) * radius * 0.4, math.sin(a - 0.15) * radius * 0.4)
              ..lineTo(math.cos(a + 0.15) * radius * 0.45, math.sin(a + 0.15) * radius * 0.45)..close(),
            Paint()..color = Colors.white.withValues(alpha: 0.2));
        }
      case HexTier.diamond:
        for (int i = 0; i < 12; i++) {
          final a = (math.pi / 6) * i;
          canvas.drawLine(Offset.zero, Offset(math.cos(a) * radius * 0.45, math.sin(a) * radius * 0.45),
            Paint()..color = Colors.white.withValues(alpha: 0.1 + (i.isEven ? 0.08 : 0))..strokeWidth = 0.5);
        }
        canvas.drawCircle(Offset.zero, radius * 0.06, Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
  }

  void _drawStar(Canvas canvas, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outer = (math.pi * 2 / 5) * i - math.pi / 2;
      final inner = outer + math.pi / 5;
      if (i == 0) { path.moveTo(math.cos(outer) * r, math.sin(outer) * r); }
      else { path.lineTo(math.cos(outer) * r, math.sin(outer) * r); }
      path.lineTo(math.cos(inner) * r * 0.4, math.sin(inner) * r * 0.4);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  Path _hexPath(double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final a = (math.pi / 3) * i - math.pi / 2;
      if (i == 0) { path.moveTo(r * math.cos(a), r * math.sin(a)); }
      else { path.lineTo(r * math.cos(a), r * math.sin(a)); }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HexTrophyPainter old) =>
      tier != old.tier || division != old.division || glowPulse != old.glowPulse;
}

/// Row showing all 6 tier hexagons with current highlighted.
class HexTierShowcase extends StatelessWidget {
  final int currentHexes;
  const HexTierShowcase({super.key, required this.currentHexes});

  @override
  Widget build(BuildContext context) {
    final currentTier = HexTier.fromHexes(currentHexes);
    final currentDiv = HexTier.divisionFromHexes(currentHexes);
    return SizedBox(
      height: 82,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: HexTier.values.map((tier) {
          final isActive = tier.level <= currentTier.level;
          final isCurrent = tier == currentTier;
          return Opacity(
            opacity: isActive ? 1.0 : 0.3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: isCurrent ? 46 : 26,
                  height: isCurrent ? 46 : 26,
                  child: CustomPaint(
                    painter: _HexTrophyPainter(
                      tier: tier,
                      division: isCurrent ? currentDiv : (isActive ? 4 : 1),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tier.label,
                  style: TextStyle(
                    fontSize: isCurrent ? 9 : 7,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                    color: isCurrent ? tier.color : (isActive ? tier.color : AppColors.grey),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
