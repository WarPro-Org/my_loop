/// Animated hex territory overlay for the journey map.
///
/// Renders owned hexes with pulsing glow, bouncy entrance animation,
/// and zoom-adaptive visibility (beacons at far zoom, full hexes up close).
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Hex sizing constants.
/// Each territory hex has a side length of ~25m (center-to-vertex radius).
/// Area per hex ≈ 1623 m². A 200m² loop yields ~1 hex, a 2000m² loop ~12 hexes.
class HexConstants {
  static const double hexRadiusMeters = 25.0;
  static const double hexAreaM2 = 1623.0; // (3√3/2) × r²
  static const double minLoopAreaForClaim = 400.0; // m² — minimum walk loop area
}

/// Animated hex territory layer that provides:
/// - Pulsing glow border effect
/// - Breathing fill opacity
/// - Bouncy scale entrance animation
/// - Zoom-adaptive rendering (beacons when zoomed out, full hexes when close)
class AnimatedHexOverlay extends StatefulWidget {
  final List<List<List<double>>> hexBoundaries;
  final Color userColor;
  final double currentZoom;
  final bool isNewCapture; // true = just captured this session (more intense glow)

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
  late AnimationController _entranceController;
  late Animation<double> _pulseAnim;
  late Animation<double> _entranceBounce;

  @override
  void initState() {
    super.initState();

    // Continuous pulse (breathing glow)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Bouncy entrance
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 800),
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
    // Re-trigger entrance when new hexes arrive
    if (widget.hexBoundaries.length != old.hexBoundaries.length) {
      _entranceController.reset();
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  /// Compute center of a hex boundary for beacon markers.
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
      animation: Listenable.merge([_pulseAnim, _entranceBounce]),
      builder: (context, _) {
        final pulse = _pulseAnim.value;
        final entrance = _entranceBounce.value;
        final zoom = widget.currentZoom;

        // Zoom thresholds
        if (zoom < 10) {
          // FAR ZOOM: Show cluster beacon
          return _buildClusterBeacon(pulse);
        } else if (zoom < 14) {
          // MEDIUM ZOOM: Show pulsing dot markers
          return _buildBeaconMarkers(pulse, entrance);
        } else {
          // CLOSE ZOOM: Show full animated hex polygons
          return _buildAnimatedPolygons(pulse, entrance);
        }
      },
    );
  }

  /// FAR ZOOM (<10): Single pulsing cluster marker with count badge.
  Widget _buildClusterBeacon(double pulse) {
    // Find the centroid of all hexes
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
    final beaconSize = 48.0 + (pulse * 8);

    return MarkerLayer(
      markers: [
        Marker(
          point: center,
          width: beaconSize + 20,
          height: beaconSize + 20,
          child: _PulsingBeacon(
            color: widget.userColor,
            pulse: pulse,
            size: beaconSize,
            count: widget.hexBoundaries.length,
          ),
        ),
      ],
    );
  }

  /// MEDIUM ZOOM (10-14): Individual pulsing dot markers per hex.
  Widget _buildBeaconMarkers(double pulse, double entrance) {
    final markers = <Marker>[];
    for (int i = 0; i < widget.hexBoundaries.length; i++) {
      final center = _computeCenter(widget.hexBoundaries[i]);
      // Stagger the pulse slightly per hex for wave effect
      final staggeredPulse = ((pulse + (i * 0.15)) % 1.0);
      final dotSize = (16.0 + staggeredPulse * 6.0) * entrance;

      markers.add(Marker(
        point: center,
        width: dotSize + 12,
        height: dotSize + 12,
        child: _HexDot(
          color: widget.userColor,
          size: dotSize,
          pulse: staggeredPulse,
          isNewCapture: widget.isNewCapture,
        ),
      ));
    }
    return MarkerLayer(markers: markers);
  }

  /// CLOSE ZOOM (14+): Full hex polygons with animated glow.
  Widget _buildAnimatedPolygons(double pulse, double entrance) {
    final baseColor = widget.userColor;
    final isNew = widget.isNewCapture;

    // Animated opacity and border width
    final fillAlpha = isNew
        ? 0.25 + (pulse * 0.2) // 0.25–0.45 for new captures
        : 0.12 + (pulse * 0.12); // 0.12–0.24 for owned
    final borderAlpha = isNew
        ? 0.7 + (pulse * 0.3) // 0.7–1.0 for new
        : 0.4 + (pulse * 0.35); // 0.4–0.75 for owned
    final borderWidth = isNew
        ? 2.5 + (pulse * 1.5) // 2.5–4.0 for new
        : 1.5 + (pulse * 1.0); // 1.5–2.5 for owned

    // Outer glow layer (slightly larger border, lower opacity)
    final glowPolygons = widget.hexBoundaries.map((boundary) {
      return Polygon(
        points: boundary.map((p) => LatLng(p[0], p[1])).toList(),
        color: Colors.transparent,
        borderColor: baseColor.withValues(alpha: borderAlpha * 0.3),
        borderStrokeWidth: borderWidth + 4.0,
      );
    }).toList();

    // Main hex fill + border
    final mainPolygons = widget.hexBoundaries.map((boundary) {
      return Polygon(
        points: boundary.map((p) => LatLng(p[0], p[1])).toList(),
        color: baseColor.withValues(alpha: fillAlpha * entrance),
        borderColor: baseColor.withValues(alpha: borderAlpha * entrance),
        borderStrokeWidth: borderWidth,
      );
    }).toList();

    // Inner highlight (white sparkle at center, subtle)
    final highlightPolygons = widget.hexBoundaries.map((boundary) {
      return Polygon(
        points: boundary.map((p) => LatLng(p[0], p[1])).toList(),
        color: Colors.white.withValues(alpha: pulse * 0.08 * entrance),
        borderColor: Colors.transparent,
        borderStrokeWidth: 0,
      );
    }).toList();

    return Stack(
      children: [
        PolygonLayer(polygons: glowPolygons),
        PolygonLayer(polygons: mainPolygons),
        PolygonLayer(polygons: highlightPolygons),
      ],
    );
  }
}

/// Pulsing beacon widget for far-zoom cluster view.
class _PulsingBeacon extends StatelessWidget {
  final Color color;
  final double pulse;
  final double size;
  final int count;

  const _PulsingBeacon({
    required this.color,
    required this.pulse,
    required this.size,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer ring pulse
        Container(
          width: size + (pulse * 16),
          height: size + (pulse * 16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.3 - (pulse * 0.2)),
              width: 2,
            ),
          ),
        ),
        // Middle glow
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.4 + pulse * 0.2),
                color.withValues(alpha: 0.1),
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
        // Center solid dot with count
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 8 + pulse * 4,
                spreadRadius: pulse * 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // Hex icon
        Positioned(
          bottom: 2,
          child: Icon(
            Icons.hexagon,
            size: 12,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// Individual hex dot marker for medium zoom.
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
        // Outer glow ring
        Container(
          width: size + 8,
          height: size + 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.3 + pulse * 0.2),
              width: 1.5,
            ),
          ),
        ),
        // Center dot
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.7 + pulse * 0.3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4 + pulse * 4,
                spreadRadius: isNewCapture ? pulse * 3 : pulse * 1.5,
              ),
            ],
          ),
          child: Icon(
            Icons.hexagon,
            size: size * 0.6,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}
