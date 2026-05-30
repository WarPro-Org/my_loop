/// Animated hex territory overlay for the journey map.
///
/// Renders owned hexes with strong dark fill, pulsing neon glow,
/// bouncy animation at ALL zoom levels, and motion graphics effects.
library;

import 'dart:async';
import 'dart:math' as math;
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

  const AnimatedHexOverlay({
    super.key,
    required this.hexBoundaries,
    required this.userColor,
    required this.currentZoom,
    this.isNewCapture = false,
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
        } else if (zoom < 14) {
          return _buildBeaconMarkers(pulse, wave, entrance);
        } else {
          return _buildAnimatedPolygons(pulse, wave, entrance);
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

  /// MEDIUM ZOOM (10-14): Bouncing hex dot markers with wave ripple.
  Widget _buildBeaconMarkers(double pulse, double wave, double entrance) {
    final markers = <Marker>[];
    final hexCount = widget.hexBoundaries.length;

    for (int i = 0; i < hexCount; i++) {
      final center = _computeCenter(widget.hexBoundaries[i]);
      // Wave ripple: each hex has a phase offset
      final phase = (wave + (i / hexCount)) % 1.0;
      final wavePulse = (math.sin(phase * 2 * math.pi) + 1) / 2;
      final dotSize = (18.0 + wavePulse * 10.0) * entrance;

      markers.add(Marker(
        point: center,
        width: dotSize + 16,
        height: dotSize + 16,
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

      // Strong dark fill — highly visible on dark map
      final fillAlpha = isNew
          ? 0.55 + (hexWave * 0.15) // 0.55–0.70 for new captures
          : 0.40 + (hexWave * 0.15); // 0.40–0.55 for owned

      // Neon glow border intensity
      final borderAlpha = isNew
          ? 0.85 + (pulse * 0.15) // 0.85–1.0
          : 0.70 + (pulse * 0.20); // 0.70–0.90

      final borderWidth = isNew
          ? 3.0 + (pulse * 1.5) // 3.0–4.5
          : 2.5 + (pulse * 1.0); // 2.5–3.5

      // Outer neon glow (wider, softer — creates the "glow" effect)
      glowPolygons.add(Polygon(
        points: points,
        color: Colors.transparent,
        borderColor: baseColor.withValues(alpha: borderAlpha * 0.35 * entrance),
        borderStrokeWidth: borderWidth + 6.0,
      ));

      // Main polygon — dark, strong, visible
      mainPolygons.add(Polygon(
        points: points,
        color: baseColor.withValues(alpha: fillAlpha * entrance),
        borderColor: baseColor.withValues(alpha: borderAlpha * entrance),
        borderStrokeWidth: borderWidth,
      ));

      // Inner shimmer — white flash sweeping through hexes
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
        PolygonLayer(polygons: glowPolygons),
        PolygonLayer(polygons: mainPolygons),
        PolygonLayer(polygons: innerPolygons),
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

/// Cooldown shield overlay — renders a pulsing shield/timer on hexes under cooldown.
///
/// Shows a translucent shield layer over protected hexes with a countdown timer
/// badge at the center of each hex cluster. Animates with a slow pulse to indicate
/// the hex is "locked" and cannot be stolen.
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
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shieldPulse, curve: Curves.easeInOut),
    );
    // Refresh countdown text every second
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
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
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
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
          // At far zoom, show shield badge at cluster center
          return _buildShieldBadges(activeCells, pulse);
        }
        // At close zoom, render shield polygons + countdown markers
        return _buildShieldPolygons(activeCells, pulse);
      },
    );
  }

  /// Far/medium zoom: shield icon badges at hex centers
  Widget _buildShieldBadges(List<TerritoryCell> cells, double pulse) {
    final markers = <Marker>[];
    for (final cell in cells) {
      final center = _computeCenter(cell.boundary);
      markers.add(Marker(
        point: center,
        width: 32,
        height: 32,
        child: Icon(
          Icons.shield,
          size: 24 + pulse * 4,
          color: Colors.cyan.withValues(alpha: 0.6 + pulse * 0.3),
        ),
      ));
    }
    return MarkerLayer(markers: markers);
  }

  /// Close zoom: translucent shield layer + countdown timer on each hex
  Widget _buildShieldPolygons(List<TerritoryCell> cells, double pulse) {
    final shieldPolygons = <Polygon>[];
    final markers = <Marker>[];

    for (final cell in cells) {
      final points = cell.boundary.map((p) => LatLng(p[0], p[1])).toList();
      final center = _computeCenter(cell.boundary);
      final remaining = cell.cooldownRemaining;

      // Shield polygon overlay — icy blue translucent with pulsing border
      shieldPolygons.add(Polygon(
        points: points,
        color: Colors.cyan.withValues(alpha: 0.08 + pulse * 0.06),
        borderColor: Colors.cyan.withValues(alpha: 0.5 + pulse * 0.3),
        borderStrokeWidth: 2.0 + pulse,
      ));

      // Countdown badge at hex center
      markers.add(Marker(
        point: center,
        width: 52,
        height: 28,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.cyan.withValues(alpha: 0.6 + pulse * 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shield,
                size: 12,
                color: Colors.cyan.withValues(alpha: 0.8 + pulse * 0.2),
              ),
              const SizedBox(width: 2),
              Text(
                _formatDuration(remaining),
                style: TextStyle(
                  color: Colors.cyan.withValues(alpha: 0.9),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
