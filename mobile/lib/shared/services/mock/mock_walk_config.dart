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

  /// Default and bounds for walking speed. The upper bound is a brisk jog, so a
  /// tester can shorten a desk run; [jitterSigmaMeters] is what keeps the measured
  /// path under the server's 9.0 m/s sustained-average gate at this bound.
  static const double defaultSpeedMps = 1.4; // average human walk
  static const double minSpeedMps = 0.5;
  static const double maxSpeedMps = 4.0; // brisk jog

  /// Stationary std-dev of the positional jitter, per axis, in metres.
  ///
  /// Calibrated against BOTH server gates, which pull in opposite directions:
  /// too little jitter and a straight route falls under the 2° bearing-std-dev
  /// smoothness floor; too much and the noise itself dominates displacement,
  /// inflating the measured path until it trips the 9.0 m/s sustained-average
  /// speed gate. Asserted in `mock_walk_engine_test.dart`.
  static const double jitterSigmaMeters = 2.5;

  /// Fix-to-fix correlation of the jitter (AR(1) coefficient per axis).
  ///
  /// Real GPS error drifts slowly; it does not re-roll every second. Independent
  /// per-fix jitter made the 8 m client noise floor keep mostly the fixes noise
  /// had pushed far, so the short 2–5 point batches the drain sends showed
  /// phantom speed and ~30% of default walks had a batch rejected by the 9.0 m/s
  /// per-batch average. At 0.9 consecutive fixes differ by only
  /// σ·√(2·(1−ρ)) ≈ 1.1 m per axis while the spread over a walk stays σ, which
  /// keeps every drain batch under the gate and bearing std-dev above 2°.
  static const double jitterCorrelation = 0.9;

  /// Default and bounds for the generated closed loop radius, in metres. The minimum
  /// is held high enough that the loop perimeter, after the client noise-floor dedup
  /// (~one retained point per [reportedAccuracyMeters]), still yields more than
  /// the game rules' minLoopPoints (20 in rules v1) retained points so the loop is actually detected:
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

  /// Walking speed used by the one-tap quick-launch scenarios. Held at the speed
  /// upper bound to keep a desk run short; the binding server constraint is the
  /// 9.0 m/s sustained-average gate, not the per-hop cap, and clearing it at this
  /// speed is what [jitterSigmaMeters] is calibrated for.
  static const double quickScenarioSpeedMps = maxSpeedMps;
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

  /// Waypoint routes only: when true and the tapped path does not already end
  /// near its first waypoint, the engine appends the first waypoint as a final
  /// anchor so the walk closes and can actually claim territory.
  final bool autoCloseLoop;

  const MockWalkConfig({
    this.enabled = false,
    this.routeType = MockRouteType.loop,
    this.startPoint = const LatLng(37.4220, -122.0841), // Googleplex; real fallback of last resort
    this.waypoints = const [],
    this.speedMps = MockWalkConstants.defaultSpeedMps,
    this.jitterEnabled = true,
    this.loopRadiusMeters = MockWalkConstants.defaultLoopRadiusMeters,
    this.straightLengthMeters = MockWalkConstants.defaultStraightLengthMeters,
    this.straightBearingDegrees = MockWalkConstants.defaultStraightBearingDegrees,
    this.autoCloseLoop = true,
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
    bool? autoCloseLoop,
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
      autoCloseLoop: autoCloseLoop ?? this.autoCloseLoop,
    );
  }

  // ── Persistence codec (saved routes, #160) ─────────────────────────────────
  //
  // Pure and tolerant by contract: [fromJson] returns null on ANY malformed
  // input instead of throwing, numeric fields are re-clamped through [copyWith],
  // an unknown route-type name falls back to [MockRouteType.loop], and `enabled`
  // is NEVER restored from disk — a persisted blob must not be able to turn the
  // simulator on by itself.

  Map<String, dynamic> toJson() => {
        'routeType': routeType.name,
        'startPoint': [startPoint.latitude, startPoint.longitude],
        'waypoints': [
          for (final wp in waypoints) [wp.latitude, wp.longitude],
        ],
        'speedMps': speedMps,
        'jitterEnabled': jitterEnabled,
        'loopRadiusMeters': loopRadiusMeters,
        'straightLengthMeters': straightLengthMeters,
        'straightBearingDegrees': straightBearingDegrees,
        'autoCloseLoop': autoCloseLoop,
      };

  static MockWalkConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final start = _latLng(json['startPoint']);
      if (start == null) return null;
      final rawWaypoints = json['waypoints'];
      final waypoints = <LatLng>[];
      if (rawWaypoints is List) {
        for (final wp in rawWaypoints) {
          final point = _latLng(wp);
          if (point == null) return null; // a corrupt waypoint corrupts the route
          waypoints.add(point);
        }
      }
      // Route through copyWith so every numeric field is re-clamped to the
      // current bounds even if the persisted values predate a bounds change.
      return const MockWalkConfig().copyWith(
        routeType: MockRouteType.values.asNameMap()[json['routeType']] ?? MockRouteType.loop,
        startPoint: start,
        waypoints: waypoints,
        speedMps: _finite(json['speedMps']),
        jitterEnabled: json['jitterEnabled'] is bool ? json['jitterEnabled'] as bool : null,
        loopRadiusMeters: _finite(json['loopRadiusMeters']),
        straightLengthMeters: _finite(json['straightLengthMeters']),
        straightBearingDegrees: _finite(json['straightBearingDegrees']),
        autoCloseLoop: json['autoCloseLoop'] is bool ? json['autoCloseLoop'] as bool : null,
      );
    } catch (_) {
      return null;
    }
  }

  static double? _finite(Object? value) {
    if (value is! num) return null;
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }

  static LatLng? _latLng(Object? value) {
    if (value is! List || value.length != 2) return null;
    final lat = _finite(value[0]);
    final lng = _finite(value[1]);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }
}

/// A tester-named route configuration persisted by the debug route store (#160).
/// Same tolerance contract as [MockWalkConfig.fromJson]: malformed → null.
class SavedMockRoute {
  final String name;
  final DateTime savedAt;
  final MockWalkConfig config;

  const SavedMockRoute({required this.name, required this.savedAt, required this.config});

  Map<String, dynamic> toJson() => {
        'name': name,
        'savedAt': savedAt.toIso8601String(),
        'config': config.toJson(),
      };

  static SavedMockRoute? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final config = MockWalkConfig.fromJson(json['config']);
    if (config == null) return null;
    final savedAt = json['savedAt'] is String ? DateTime.tryParse(json['savedAt'] as String) : null;
    return SavedMockRoute(name: name, savedAt: savedAt ?? DateTime.now(), config: config);
  }
}

/// A named one-tap test scenario surfaced as a quick-launch button on the dev
/// screen. Each [config] already sits within the clamped bounds with jitter ON,
/// so the walk it generates satisfies server anti-cheat (retained-point density
/// above the loop/claim floors, per-hop speed under the cap) by construction.
///
/// The embedded [MockWalkConfig.startPoint] is a placeholder (the const default):
/// the dev screen overrides it with the map's current centre at launch, so a tap
/// always starts the walk wherever the tester has panned to.
class MockWalkScenario {
  final String label;
  final MockWalkConfig config;
  const MockWalkScenario(this.label, this.config);
}

/// The curated set of one-tap scenarios. Deliberately small: every entry must
/// stay anti-cheat-valid and is asserted so in tests — an unbounded button grid
/// would rot and risk silently generating a server-rejected path.
class MockWalkScenarios {
  MockWalkScenarios._();

  static const quickLoop = MockWalkScenario(
    'Quick loop',
    MockWalkConfig(
      enabled: true,
      routeType: MockRouteType.loop,
      loopRadiusMeters: MockWalkConstants.defaultLoopRadiusMeters,
      speedMps: MockWalkConstants.quickScenarioSpeedMps,
    ),
  );

  static const bigLoop = MockWalkScenario(
    'Big loop',
    MockWalkConfig(
      enabled: true,
      routeType: MockRouteType.loop,
      loopRadiusMeters: MockWalkConstants.maxLoopRadiusMeters,
      speedMps: MockWalkConstants.quickScenarioSpeedMps,
    ),
  );

  static const straight = MockWalkScenario(
    'Straight',
    MockWalkConfig(
      enabled: true,
      routeType: MockRouteType.straight,
      straightLengthMeters: MockWalkConstants.defaultStraightLengthMeters,
      speedMps: MockWalkConstants.quickScenarioSpeedMps,
    ),
  );

  /// Display order for the quick-launch row. "Last used" is intentionally absent
  /// — it re-runs the live [mockWalkConfigProvider] state and is handled in the UI.
  static const all = <MockWalkScenario>[quickLoop, bigLoop, straight];
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
