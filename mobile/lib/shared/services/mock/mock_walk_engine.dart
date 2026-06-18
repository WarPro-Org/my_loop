/// MyLoop — Mock Walk Simulation: engine (#29)
///
/// Turns a [MockWalkConfig] route into a synthetic but anti-cheat-valid stream of
/// GPS [Position] fixes that look like a real human walk:
///   • route is densified to ~1 fix/sec at the configured walking speed,
///   • each fix gets Gaussian positional jitter so the path is not a spoof-smooth
///     line (server rejects bearing std-dev < 2°),
///   • fixes are emitted in real wall-clock time so the per-hop distance/elapsed
///     speed stays under the server cap.
///
/// Geometry uses a local equirectangular approximation — accurate to centimetres
/// over the sub-kilometre routes the simulator generates.
library;

import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'mock_walk_config.dart';

/// Metres per degree of latitude (WGS-84 mean). Longitude scales by cos(latitude).
const double _metersPerDegLat = 111320.0;

/// One plotted step along the route: position + the heading used to reach it.
class MockRoutePoint {
  final double lat;
  final double lng;
  final double headingDegrees;
  const MockRoutePoint(this.lat, this.lng, this.headingDegrees);
}

class MockWalkEngine {
  final MockWalkConfig config;
  final Random _random;

  /// Plotted route is computed once per engine and reused, so a one-shot fix
  /// ([generatePositions]/[MockLocationService.getCurrentPosition]) and the live
  /// [stream] share the SAME jittered points instead of re-rolling the RNG and
  /// diverging. One [MockLocationService] owns one engine, so a single walk is
  /// internally consistent (and reproducible when a seeded [Random] is supplied).
  List<MockRoutePoint>? _plotted;

  MockWalkEngine(this.config, {Random? random}) : _random = random ?? Random();

  // ──────────────────────────────────────────────────────────────────────────
  // Route anchors
  // ──────────────────────────────────────────────────────────────────────────

  /// Ordered vertices of the route, before densification. Always >= 2 points.
  List<LatLng> buildRouteAnchors() {
    switch (config.routeType) {
      case MockRouteType.loop:
        return _closedPolygon(
          config.startPoint,
          config.loopRadiusMeters,
          MockWalkConstants.loopVertexCount,
        );
      case MockRouteType.straight:
        final end = _offsetByBearing(
          config.startPoint,
          config.straightBearingDegrees,
          config.straightLengthMeters,
        );
        return [config.startPoint, end];
      case MockRouteType.multiWaypoint:
        if (config.waypoints.length >= 2) return List.of(config.waypoints);
        // Degenerate config: fall back to a short straight leg so the run is valid.
        final end = _offsetByBearing(
          config.startPoint,
          MockWalkConstants.defaultStraightBearingDegrees,
          MockWalkConstants.defaultStraightLengthMeters,
        );
        return [config.startPoint, end];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Densify + jitter (deterministic given the seeded Random — used by tests)
  // ──────────────────────────────────────────────────────────────────────────

  /// Walks the anchor polyline, emitting a jittered fix every [MockWalkConstants.tickInterval]
  /// at [MockWalkConfig.speedMps]. Pure geometry — no timing — so it is unit-testable.
  /// Memoized: computed once, then reused by both [generatePositions] and [stream].
  List<MockRoutePoint> plotPoints() => _plotted ??= _computePlot();

  List<MockRoutePoint> _computePlot() {
    final anchors = buildRouteAnchors();
    final stepMeters = config.speedMps * MockWalkConstants.tickInterval.inMilliseconds / 1000.0;
    final points = <MockRoutePoint>[];

    // Emit the start fix.
    final first = _jitter(anchors.first);
    points.add(MockRoutePoint(first.latitude, first.longitude, 0.0));

    for (var seg = 0; seg < anchors.length - 1; seg++) {
      final from = anchors[seg];
      final to = anchors[seg + 1];
      final segLength = _distance(from, to);
      if (segLength <= 0) continue;

      // Step along this segment at the walking pace.
      for (var travelled = stepMeters; travelled <= segLength; travelled += stepMeters) {
        final frac = travelled / segLength;
        final clean = LatLng(
          from.latitude + (to.latitude - from.latitude) * frac,
          from.longitude + (to.longitude - from.longitude) * frac,
        );
        final jittered = _jitter(clean);
        final prev = points.last;
        final heading = _bearing(prev.lat, prev.lng, jittered.latitude, jittered.longitude);
        points.add(MockRoutePoint(jittered.latitude, jittered.longitude, heading));
      }
    }

    // Guarantee the final anchor is represented (last partial step may fall short).
    final lastAnchor = _jitter(anchors.last);
    final prev = points.last;
    if (_distance(LatLng(prev.lat, prev.lng), lastAnchor) > 0.5) {
      final heading = _bearing(prev.lat, prev.lng, lastAnchor.latitude, lastAnchor.longitude);
      points.add(MockRoutePoint(lastAnchor.latitude, lastAnchor.longitude, heading));
    }

    return points;
  }

  /// Maps plotted points to [Position]s with timestamps spaced by the tick interval,
  /// starting at [startTime]. Deterministic — used by tests to assert speed/bearing.
  List<Position> generatePositions({required DateTime startTime}) {
    final plotted = plotPoints();
    final tick = MockWalkConstants.tickInterval;
    return [
      for (var i = 0; i < plotted.length; i++)
        _toPosition(plotted[i], startTime.add(tick * i)),
    ];
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Live stream (real-time pacing)
  // ──────────────────────────────────────────────────────────────────────────

  /// Emits fixes in real wall-clock time, one per [MockWalkConstants.tickInterval],
  /// timestamped at emission. Cancelling the subscription stops the walk.
  Stream<Position> stream() async* {
    for (final point in plotPoints()) {
      yield _toPosition(point, DateTime.now());
      await Future<void>.delayed(MockWalkConstants.tickInterval);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Geometry helpers
  // ──────────────────────────────────────────────────────────────────────────

  Position _toPosition(MockRoutePoint p, DateTime timestamp) {
    return Position(
      latitude: p.lat,
      longitude: p.lng,
      timestamp: timestamp,
      accuracy: MockWalkConstants.reportedAccuracyMeters,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: p.headingDegrees,
      headingAccuracy: 0,
      speed: config.speedMps,
      speedAccuracy: 0,
      isMocked: true,
    );
  }

  LatLng _jitter(LatLng point) {
    if (!config.jitterEnabled) return point;
    final north = _gaussian() * MockWalkConstants.jitterSigmaMeters;
    final east = _gaussian() * MockWalkConstants.jitterSigmaMeters;
    return _offsetMeters(point, north, east);
  }

  /// Standard normal sample via the Box–Muller transform.
  double _gaussian() {
    final u1 = _random.nextDouble().clamp(1e-9, 1.0);
    final u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  static List<LatLng> _closedPolygon(LatLng centre, double radiusMeters, int vertices) {
    final pts = <LatLng>[];
    for (var i = 0; i < vertices; i++) {
      final angle = 2 * pi * i / vertices;
      pts.add(_offsetMeters(centre, radiusMeters * cos(angle), radiusMeters * sin(angle)));
    }
    pts.add(pts.first); // close the loop back to the first vertex
    return pts;
  }

  static LatLng _offsetByBearing(LatLng from, double bearingDegrees, double distanceMeters) {
    final rad = bearingDegrees * pi / 180.0;
    return _offsetMeters(from, distanceMeters * cos(rad), distanceMeters * sin(rad));
  }

  static LatLng _offsetMeters(LatLng from, double northMeters, double eastMeters) {
    final dLat = northMeters / _metersPerDegLat;
    final dLng = eastMeters / (_metersPerDegLat * cos(from.latitude * pi / 180.0));
    return LatLng(from.latitude + dLat, from.longitude + dLng);
  }

  static double _distance(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.bearingBetween(lat1, lng1, lat2, lng2);
  }
}
