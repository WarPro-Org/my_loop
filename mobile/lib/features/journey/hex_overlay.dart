/// Animated hex territory overlay for the journey map.
///
/// Renders owned hexes with strong dark fill, pulsing neon glow,
/// bouncy animation at ALL zoom levels, and motion graphics effects.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/shared/models/territory_cell.dart';

/// Hex sizing constants — match H3 resolution 11 geometry.
class HexConstants {
  static const double hexRadiusMeters = 29.0; // circumradius at H3 res 11
  static const double hexAreaM2 = 2150.0;
  static const double minLoopAreaForClaim = 5000.0; // matches API MinFillAreaSquareMeters
}

/// Animated hex territory layer with:
/// - Strong dark fill visible on dark map
/// - Neon glow border that pulses
/// - Bouncy animation at ALL zoom levels
/// - Motion wave effect (hexes pulse in sequence like a heartbeat)
class AnimatedHexOverlay extends StatefulWidget {
  final List<List<List<double>>> hexBoundaries;
  final Color userColor;
  final double currentZoom;
  final bool isNewCapture;
  final bool solidMode;

  const AnimatedHexOverlay({
    super.key,
    required this.hexBoundaries,
    required this.userColor,
    required this.currentZoom,
    this.isNewCapture = false,
    this.solidMode = false,
  });

  @override
  State<AnimatedHexOverlay> createState() => _AnimatedHexOverlayState();
}

class _AnimatedHexOverlayState extends State<AnimatedHexOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _entranceController;
  late Animation<double> _pulseAnim;
  late Animation<double> _waveAnim;
  late Animation<double> _entranceBounce;

  @override
  void initState() {
    super.initState();

    // Continuous pulse — neon glow breathing
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Wave animation — hexes light up in sequence (motion graphics)
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();
    _waveAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_waveController);

    // Bouncy entrance
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _entranceBounce = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.elasticOut),
    );
    _entranceController.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedHexOverlay old) {
    super.didUpdateWidget(old);
    if (widget.hexBoundaries.length != old.hexBoundaries.length) {
      _entranceController.reset();
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  LatLng _computeCenter(List<List<double>> boundary) {
    double latSum = 0, lngSum = 0;
    for (final p in boundary) {
      latSum += p[0];
      lngSum += p[1];
    }
    return LatLng(latSum / boundary.length, lngSum / boundary.length);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hexBoundaries.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _waveAnim, _entranceBounce]),
      builder: (context, _) {
        final pulse = _pulseAnim.value;
        final wave = _waveAnim.value;
        final entrance = _entranceBounce.value;
        final zoom = widget.currentZoom;

        if (zoom < 10) {
          return _buildClusterBeacon(pulse);
        } else if (widget.solidMode) {
          return _buildAnimatedPolygons(pulse, wave, entrance);
        } else {
          return _buildBeaconMarkers(pulse, wave, entrance);
        }
      },
    );
  }

  /// FAR ZOOM (<10): Pulsing cluster beacon with count.
  Widget _buildClusterBeacon(double pulse) {
    double latSum = 0, lngSum = 0;
    int count = 0;
    for (final boundary in widget.hexBoundaries) {
      for (final p in boundary) {
        latSum += p[0];
        lngSum += p[1];
        count++;
      }
    }
    final center = LatLng(latSum / count, lngSum / count);

    return MarkerLayer(
      markers: [
        Marker(
          point: center,
          width: 72,
          height: 72,
          child: _PulsingBeacon(
            color: widget.userColor,
            pulse: pulse,
            count: widget.hexBoundaries.length,
          ),
        ),
      ],
    );
  }

  /// BEACON MARKERS (zoom 10+): Bouncing hex dot markers with wave ripple.
  /// Used at all non-solid zoom levels — consistent look everywhere.
  Widget _buildBeaconMarkers(double pulse, double wave, double entrance) {
    final markers = <Marker>[];
    final hexCount = widget.hexBoundaries.length;
    final zoom = widget.currentZoom;

    // Scale rings up at close zoom so they feel proportional to actual hex size.
    // At zoom 14 → ×1.0, zoom 15 → ×1.4, zoom 16 → ×2.0, zoom 17+ → capped ×2.8
    final zoomScale = zoom < 14
        ? 1.0
        : math.min(2.8, math.pow(2.0, (zoom - 14) / 2).toDouble());

    for (int i = 0; i < hexCount; i++) {
      final center = _computeCenter(widget.hexBoundaries[i]);
      // Wave ripple: each hex has a phase offset
      final phase = (wave + (i / hexCount)) % 1.0;
      final wavePulse = (math.sin(phase * 2 * math.pi) + 1) / 2;
      final dotSize = (18.0 + wavePulse * 10.0) * entrance * zoomScale;

      markers.add(Marker(
        point: center,
        width: dotSize + 16 * zoomScale,
        height: dotSize + 16 * zoomScale,
        child: _HexDot(
          color: widget.userColor,
          size: dotSize,
          pulse: wavePulse,
          isNewCapture: widget.isNewCapture,
        ),
      ));
    }
    return MarkerLayer(markers: markers);
  }

  /// CLOSE ZOOM (14+): Full hex polygons with dark fill, neon glow, wave motion.
  /// Only used when solidMode is ON — renders the classic neon glow polygon style.
  Widget _buildAnimatedPolygons(double pulse, double wave, double entrance) {
    final baseColor = widget.userColor;
    final isNew = widget.isNewCapture;
    final hexCount = widget.hexBoundaries.length;

    final glowPolygons = <Polygon>[];
    final mainPolygons = <Polygon>[];
    final innerPolygons = <Polygon>[];

    for (int i = 0; i < hexCount; i++) {
      final boundary = widget.hexBoundaries[i];
      final points = boundary.map((p) => LatLng(p[0], p[1])).toList();

      // Per-hex wave phase — creates a sweeping light effect
      final phase = (wave + (i / math.max(hexCount, 1))) % 1.0;
      final hexWave = (math.sin(phase * 2 * math.pi) + 1) / 2;

      final fillAlpha = isNew
          ? 0.55 + (hexWave * 0.15)
          : 0.40 + (hexWave * 0.15);

      final borderAlpha = isNew
          ? 0.85 + (pulse * 0.15)
          : 0.70 + (pulse * 0.20);

      final borderWidth = isNew
          ? 3.0 + (pulse * 1.5)
          : 2.5 + (pulse * 1.0);

      glowPolygons.add(Polygon(
        points: points,
        color: Colors.transparent,
        borderColor: baseColor.withValues(alpha: borderAlpha * 0.35 * entrance),
        borderStrokeWidth: borderWidth + 6.0,
      ));

      mainPolygons.add(Polygon(
        points: points,
        color: baseColor.withValues(alpha: fillAlpha * entrance),
        borderColor: baseColor.withValues(alpha: borderAlpha * entrance),
        borderStrokeWidth: borderWidth,
      ));

      final shimmerAlpha = hexWave > 0.7 ? (hexWave - 0.7) / 0.3 * 0.18 : 0.0;
      innerPolygons.add(Polygon(
        points: points,
        color: Colors.white.withValues(alpha: shimmerAlpha * entrance),
        borderColor: Colors.transparent,
        borderStrokeWidth: 0,
      ));
    }

    return Stack(
      children: [
        if (glowPolygons.isNotEmpty) PolygonLayer(polygons: glowPolygons),
        PolygonLayer(polygons: mainPolygons),
        if (innerPolygons.isNotEmpty) PolygonLayer(polygons: innerPolygons),
      ],
    );
  }
}

/// Pulsing beacon for far-zoom cluster view.
class _PulsingBeacon extends StatelessWidget {
  final Color color;
  final double pulse;
  final int count;

  const _PulsingBeacon({
    required this.color,
    required this.pulse,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer expanding ring
        Container(
          width: 60 + (pulse * 12),
          height: 60 + (pulse * 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.4 - (pulse * 0.3)),
              width: 2.5,
            ),
          ),
        ),
        // Middle glow
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.6 + pulse * 0.2),
                color.withValues(alpha: 0.15),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Center count badge
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.7),
                blurRadius: 10 + pulse * 6,
                spreadRadius: pulse * 3,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual hex dot marker for medium zoom — bouncy, glowing.
class _HexDot extends StatelessWidget {
  final Color color;
  final double size;
  final double pulse;
  final bool isNewCapture;

  const _HexDot({
    required this.color,
    required this.size,
    required this.pulse,
    required this.isNewCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow ring
        Container(
          width: size + 10,
          height: size + 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.4 + pulse * 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 6 + pulse * 6,
                spreadRadius: pulse * 2,
              ),
            ],
          ),
        ),
        // Center dot
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.8 + pulse * 0.2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 5 + pulse * 5,
                spreadRadius: isNewCapture ? pulse * 4 : pulse * 2,
              ),
            ],
          ),
          child: Icon(
            Icons.hexagon,
            size: size * 0.55,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}

/// Cooldown shield overlay — premium glassmorphic design with animated timer.
///
/// Renders a frosted-glass shield layer over protected hexes with a sleek
/// countdown pill at each hex center. Uses the app's Nunito font and custom
/// painted shield icon for a polished Duolingo-level look.
class CooldownHexOverlay extends StatefulWidget {
  final List<TerritoryCell> cooldownCells;
  final double currentZoom;

  const CooldownHexOverlay({
    super.key,
    required this.cooldownCells,
    required this.currentZoom,
  });

  @override
  State<CooldownHexOverlay> createState() => _CooldownHexOverlayState();
}

class _CooldownHexOverlayState extends State<CooldownHexOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _shieldPulse;
  late Animation<double> _pulseAnim;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _shieldPulse = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shieldPulse, curve: Curves.easeInOut),
    );
    _countdownTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _shieldPulse.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  LatLng _computeCenter(List<List<double>> boundary) {
    double latSum = 0, lngSum = 0;
    for (final p in boundary) {
      latSum += p[0];
      lngSum += p[1];
    }
    return LatLng(latSum / boundary.length, lngSum / boundary.length);
  }

  @override
  Widget build(BuildContext context) {
    final activeCells = widget.cooldownCells.where((c) => c.isOnCooldown).toList();
    if (activeCells.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        final pulse = _pulseAnim.value;
        final zoom = widget.currentZoom;

        if (zoom < 14) {
          return _buildFarZoomIndicators(activeCells, pulse);
        }
        return _buildCloseZoomShield(activeCells, pulse);
      },
    );
  }

  /// Far/medium zoom: compact glowing lock indicators
  Widget _buildFarZoomIndicators(List<TerritoryCell> cells, double pulse) {
    final markers = <Marker>[];
    for (final cell in cells) {
      final center = _computeCenter(cell.boundary);
      markers.add(Marker(
        point: center,
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF4AEADC).withValues(alpha: 0.7 + pulse * 0.3),
                const Color(0xFF1B8A80).withValues(alpha: 0.3),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4AEADC).withValues(alpha: 0.4 + pulse * 0.3),
                blurRadius: 8 + pulse * 4,
                spreadRadius: pulse * 2,
              ),
            ],
          ),
          child: Center(
            child: CustomPaint(
              size: const Size(14, 14),
              painter: _ShieldIconPainter(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ));
    }
    return MarkerLayer(markers: markers);
  }

  /// Close zoom: frosted shield polygon + premium countdown pill
  Widget _buildCloseZoomShield(List<TerritoryCell> cells, double pulse) {
    final shieldPolygons = <Polygon>[];
    final markers = <Marker>[];

    for (final cell in cells) {
      final points = cell.boundary.map((p) => LatLng(p[0], p[1])).toList();
      final center = _computeCenter(cell.boundary);
      final remaining = cell.cooldownRemaining;

      // Frosted shield polygon — subtle teal with soft glow border
      shieldPolygons.add(Polygon(
        points: points,
        color: const Color(0xFF4AEADC).withValues(alpha: 0.06 + pulse * 0.04),
        borderColor: const Color(0xFF4AEADC).withValues(alpha: 0.35 + pulse * 0.25),
        borderStrokeWidth: 1.5 + pulse * 0.5,
      ));

      // Premium countdown pill — glassmorphic with gradient
      markers.add(Marker(
        point: center,
        width: 48,
        height: 24,
        child: _CooldownPill(
          remaining: remaining,
          pulse: pulse,
          formatDuration: _formatDuration,
        ),
      ));
    }

    return Stack(
      children: [
        PolygonLayer(polygons: shieldPolygons),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

/// Premium glassmorphic countdown pill widget.
class _CooldownPill extends StatelessWidget {
  final Duration remaining;
  final double pulse;
  final String Function(Duration) formatDuration;

  const _CooldownPill({
    required this.remaining,
    required this.pulse,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A3A38).withValues(alpha: 0.85),
            const Color(0xFF0D2926).withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF4AEADC).withValues(alpha: 0.4 + pulse * 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4AEADC).withValues(alpha: 0.15 + pulse * 0.1),
            blurRadius: 6 + pulse * 3,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(10, 11),
            painter: _ShieldIconPainter(
              color: const Color(0xFF4AEADC).withValues(alpha: 0.8 + pulse * 0.2),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            formatDuration(remaining),
            style: TextStyle(
              fontFamily: 'Nunito',
              color: const Color(0xFF4AEADC).withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painted shield icon — cleaner than Material Icons.shield.
/// Draws a modern shield silhouette with rounded top and pointed bottom.
class _ShieldIconPainter extends CustomPainter {
  final Color color;

  _ShieldIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = ui.Path();
    final w = size.width;
    final h = size.height;

    // Shield shape: rounded top, tapers to point at bottom
    path.moveTo(w * 0.5, 0); // top center
    path.quadraticBezierTo(w * 0.95, h * 0.05, w, h * 0.25); // top-right curve
    path.lineTo(w * 0.92, h * 0.55); // right side
    path.quadraticBezierTo(w * 0.75, h * 0.8, w * 0.5, h); // bottom-right to point
    path.quadraticBezierTo(w * 0.25, h * 0.8, w * 0.08, h * 0.55); // bottom-left
    path.lineTo(0, h * 0.25); // left side
    path.quadraticBezierTo(w * 0.05, h * 0.05, w * 0.5, 0); // top-left curve
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ShieldIconPainter oldDelegate) => color != oldDelegate.color;
}
