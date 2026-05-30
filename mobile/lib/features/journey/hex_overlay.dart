/// Animated hex territory overlay for the journey map.
///
/// Renders owned hexes with strong dark fill, pulsing neon glow,
/// bouncy animation at ALL zoom levels, and motion graphics effects.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Hex sizing constants.
class HexConstants {
  static const double hexRadiusMeters = 25.0;
  static const double hexAreaM2 = 1623.0;
  static const double minLoopAreaForClaim = 400.0;
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

  /// CLOSE ZOOM (14+): Full hex polygons with 3D depth, neon glow, wave motion.
  Widget _buildAnimatedPolygons(double pulse, double wave, double entrance) {
    final baseColor = widget.userColor;
    final isNew = widget.isNewCapture;
    final hexCount = widget.hexBoundaries.length;

    final glowPolygons = <Polygon>[];
    final mainPolygons = <Polygon>[];
    final depthPolygons = <Polygon>[];

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

      // 3D depth effect: top-highlight layer (white gradient on upper half)
      // and inner shimmer sweep combined
      final highlightAlpha = 0.08 + (hexWave * 0.06); // subtle top shine
      depthPolygons.add(Polygon(
        points: points,
        color: Colors.white.withValues(alpha: highlightAlpha * entrance),
        borderColor: Colors.transparent,
        borderStrokeWidth: 0,
      ));
    }

    // 3D shadow layer: offset polygons slightly down to simulate depth
    final shadowPolygons = <Polygon>[];
    for (int i = 0; i < hexCount; i++) {
      final boundary = widget.hexBoundaries[i];
      // Offset points slightly south (lower lat) for shadow
      final shadowPoints = boundary.map((p) => LatLng(p[0] - 0.000015, p[1])).toList();
      shadowPolygons.add(Polygon(
        points: shadowPoints,
        color: Colors.black.withValues(alpha: 0.25 * entrance),
        borderColor: Colors.transparent,
        borderStrokeWidth: 0,
      ));
    }

    return Stack(
      children: [
        PolygonLayer(polygons: shadowPolygons),
        PolygonLayer(polygons: glowPolygons),
        PolygonLayer(polygons: mainPolygons),
        PolygonLayer(polygons: depthPolygons),
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
