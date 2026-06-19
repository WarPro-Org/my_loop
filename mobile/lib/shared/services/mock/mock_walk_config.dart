/// MyLoop — Mock Walk Simulation: configuration (#29)
///
/// Debug-only test harness that lets a tester simulate an outdoor walk from
/// their desk. The config below is consumed by [MockWalkEngine] (route → timed,
/// jittered GPS stream) and surfaced through the dev screen.
///
/// Nothing here is reachable in a release build: the provider that swaps in the
/// mock is guarded by `kDebugMode` (see `location_service.dart`), as is the dev
/// route and the request header.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Tuning constants for the simulator. Kept out of the gameplay `AppConstants`
/// because they are debug-only and never affect a real walk.
class MockWalkConstants {
  MockWalkConstants._();

  /// Request header attached (debug only) while the simulator is active, so the
  /// backend routes the request's logs to MockLogs/. MUST match the .NET constant
  /// `InfrastructureDefaults.MockRequestHeader`.
  static const String requestHeader = 'X-MyLoop-Mock';
  static const String requestHeaderValue = '1';

  /// Wall-clock interval between synthesized GPS fixes (~1 Hz, like a real device).
  static const Duration tickInterval = Duration(seconds: 1);

  /// Default and bounds for walking speed. The upper bound is held well under the
  /// server anti-cheat cap (8.33 m/s) so even with jitter no hop is rejected, while
  /// still letting a tester speed a run up to a brisk jog to shorten it.
  static const double defaultSpeedMps = 1.4; // average human walk
  static const double minSpeedMps = 0.5;
  static const double maxSpeedMps = 4.0; // brisk jog; << 8.33 m/s cap

  /// Std-dev of per-fix positional jitter, in metres. Calibrated so consecutive
  /// retained points (~5 m apart after the client noise filter) have a bearing
  /// std-dev comfortably above the server's 2° smoothness floor — i.e. even a
  /// "straight" route reads as a real human walk, not a spoofed line.
  static const double jitterSigmaMeters = 4.0;

  /// Default and bounds for the generated closed loop radius, in metres. The minimum
  /// is held high enough that the loop perimeter, after the client noise-floor dedup
  /// (~one retained point per [reportedAccuracyMeters]), still yields more than
  /// LoopDetector.minLoopPoints (20) retained points so the loop is actually detected:
  /// min perimeter 2·π·30 ≈ 188 m / 8 m ≈ 23 points.
  static const double defaultLoopRadiusMeters = 45.0;
  static const double minLoopRadiusMeters = 30.0;
  static const double maxLoopRadiusMeters = 120.0;

  /// Number of vertices used to approximate the generated loop polygon.
  static const int loopVertexCount = 8;

  /// Default and bounds for a generated straight route length, in metres. The minimum
  /// keeps retained points above AppConstants.minGpsPointsPerClaim (10): 100 m / 8 m ≈ 12.
  static const double defaultStraightLengthMeters = 220.0;
  static const double minStraightLengthMeters = 100.0;
  static const double maxStraightLengthMeters = 500.0;

  /// Default compass bearing (degrees) for a generated straight route.
  static const double defaultStraightBearingDegrees = 0.0;

  /// Nominal GPS horizontal accuracy reported on synthesized fixes, in metres.
  static const double reportedAccuracyMeters = 8.0;
}

/// Shape of the route the simulator walks.
enum MockRouteType {
  /// A closed polygon around the start point — exercises loop detection + capture.
  loop,

  /// A single straight line from the start point along a bearing.
  straight,

  /// An open polyline visiting tapped waypoints in order ("exact multiple locations").
  multiWaypoint,
}

/// Immutable configuration for a simulated walk.
class MockWalkConfig {
  /// When false the real [LocationService] is used; the simulator is inert.
  final bool enabled;
  final MockRouteType routeType;

  /// Anchor used by generated routes (loop centre / straight origin). Also the
  /// first waypoint for [MockRouteType.multiWaypoint] when no taps exist yet.
  final LatLng startPoint;

  /// Tester-tapped waypoints (used by [MockRouteType.multiWaypoint]).
  final List<LatLng> waypoints;

  final double speedMps;
  final bool jitterEnabled;
  final double loopRadiusMeters;
  final double straightLengthMeters;
  final double straightBearingDegrees;

  const MockWalkConfig({
    this.enabled = false,
    this.routeType = MockRouteType.loop,
    this.startPoint = const LatLng(37.4220, -122.0841), // Googleplex; overridden on open
    this.waypoints = const [],
    this.speedMps = MockWalkConstants.defaultSpeedMps,
    this.jitterEnabled = true,
    this.loopRadiusMeters = MockWalkConstants.defaultLoopRadiusMeters,
    this.straightLengthMeters = MockWalkConstants.defaultStraightLengthMeters,
    this.straightBearingDegrees = MockWalkConstants.defaultStraightBearingDegrees,
  });

  MockWalkConfig copyWith({
    bool? enabled,
    MockRouteType? routeType,
    LatLng? startPoint,
    List<LatLng>? waypoints,
    double? speedMps,
    bool? jitterEnabled,
    double? loopRadiusMeters,
    double? straightLengthMeters,
    double? straightBearingDegrees,
  }) {
    return MockWalkConfig(
      enabled: enabled ?? this.enabled,
      routeType: routeType ?? this.routeType,
      startPoint: startPoint ?? this.startPoint,
      waypoints: waypoints ?? this.waypoints,
      speedMps: (speedMps ?? this.speedMps)
          .clamp(MockWalkConstants.minSpeedMps, MockWalkConstants.maxSpeedMps),
      jitterEnabled: jitterEnabled ?? this.jitterEnabled,
      loopRadiusMeters: (loopRadiusMeters ?? this.loopRadiusMeters)
          .clamp(MockWalkConstants.minLoopRadiusMeters, MockWalkConstants.maxLoopRadiusMeters),
      straightLengthMeters: (straightLengthMeters ?? this.straightLengthMeters)
          .clamp(MockWalkConstants.minStraightLengthMeters, MockWalkConstants.maxStraightLengthMeters),
      straightBearingDegrees: straightBearingDegrees ?? this.straightBearingDegrees,
    );
  }
}

/// Riverpod state for the simulator config. Side effect: mirrors [MockWalkConfig.enabled]
/// into [MockWalkMode] so the Dio interceptor can tag outbound requests without taking a
/// Riverpod dependency.
class MockWalkConfigNotifier extends Notifier<MockWalkConfig> {
  @override
  MockWalkConfig build() {
    final initial = const MockWalkConfig();
    MockWalkMode.active = initial.enabled;
    // Fail safe: if this provider is disposed (e.g. across a hot restart) the global
    // must not keep tagging requests as mock — reset it so it can never lag the config.
    ref.onDispose(() => MockWalkMode.active = false);
    return initial;
  }

  void update(MockWalkConfig config) {
    state = config;
    MockWalkMode.active = config.enabled;
  }
}

final mockWalkConfigProvider =
    NotifierProvider<MockWalkConfigNotifier, MockWalkConfig>(MockWalkConfigNotifier.new);

/// Process-global flag bridging the simulator and the Dio request interceptor.
///
/// Set from [MockWalkConfigNotifier] whenever the config's `enabled` changes. The
/// interceptor reads it (under `kDebugMode`) to attach the `X-MyLoop-Mock` header so
/// the backend routes the request's logs to MockLogs/. It marks logging only — the
/// server never branches game logic on it.
class MockWalkMode {
  MockWalkMode._();
  static bool active = false;
}
