/// Game rules the app uses (FR1). The server owns them (`GameRules` in appsettings.json) and
/// sends this app-safe subset from `GET /api/rules`; anti-cheat numbers never reach the app. The auto-end vehicle
/// speed (FR2) is a walk rule above both anti-cheat speeds, not a cheat check.
///
/// Mirrors `ClientRules` in api/MyLoop.Modules.Rules/ClientRules.cs — keep field names in sync.
library;

class GameRules {
  final int version;
  final double loopClosureDistanceMeters;
  final int minLoopPoints;
  final int loopSkipNeighbors;
  final double gpsAccuracyThresholdMeters;

  /// Loops smaller than this capture nothing (FR2, O11), so the phone's loop check matches the server's.
  final double minLoopAreaSquareMeters;

  /// FR2 auto-end (#34): a walk faster than [autoEndVehicleSpeedMetersPerSecond] on average for
  /// [autoEndVehicleSeconds] is a vehicle ride; staying within [autoEndStillRadiusMeters] with less than
  /// [autoEndStillMaxWalkedMeters] of recorded path for [autoEndStillSeconds] is standing still.
  final double autoEndVehicleSpeedMetersPerSecond;
  final int autoEndVehicleSeconds;
  final double autoEndStillRadiusMeters;
  final int autoEndStillSeconds;
  final double autoEndStillMaxWalkedMeters;

  const GameRules({
    required this.version,
    required this.loopClosureDistanceMeters,
    required this.minLoopPoints,
    required this.loopSkipNeighbors,
    required this.gpsAccuracyThresholdMeters,
    required this.minLoopAreaSquareMeters,
    required this.autoEndVehicleSpeedMetersPerSecond,
    required this.autoEndVehicleSeconds,
    required this.autoEndStillRadiusMeters,
    required this.autoEndStillSeconds,
    required this.autoEndStillMaxWalkedMeters,
  });

  /// Throws [FormatException] when a field is missing or has the wrong type, so a bad server
  /// response or a corrupted saved copy is rejected instead of half-applied.
  factory GameRules.fromJson(Map<String, dynamic> json) {
    T field<T>(String key) {
      final value = json[key];
      if (value is num && T == double) return value.toDouble() as T;
      if (value is T) return value;
      throw FormatException('GameRules: "$key" is missing or not a $T');
    }

    return GameRules(
      version: field<int>('version'),
      loopClosureDistanceMeters: field<double>('loopClosureDistanceMeters'),
      minLoopPoints: field<int>('minLoopPoints'),
      loopSkipNeighbors: field<int>('loopSkipNeighbors'),
      gpsAccuracyThresholdMeters: field<double>('gpsAccuracyThresholdMeters'),
      minLoopAreaSquareMeters: field<double>('minLoopAreaSquareMeters'),
      autoEndVehicleSpeedMetersPerSecond: field<double>('autoEndVehicleSpeedMetersPerSecond'),
      autoEndVehicleSeconds: field<int>('autoEndVehicleSeconds'),
      autoEndStillRadiusMeters: field<double>('autoEndStillRadiusMeters'),
      autoEndStillSeconds: field<int>('autoEndStillSeconds'),
      autoEndStillMaxWalkedMeters: field<double>('autoEndStillMaxWalkedMeters'),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'loopClosureDistanceMeters': loopClosureDistanceMeters,
        'minLoopPoints': minLoopPoints,
        'loopSkipNeighbors': loopSkipNeighbors,
        'gpsAccuracyThresholdMeters': gpsAccuracyThresholdMeters,
        'minLoopAreaSquareMeters': minLoopAreaSquareMeters,
        'autoEndVehicleSpeedMetersPerSecond': autoEndVehicleSpeedMetersPerSecond,
        'autoEndVehicleSeconds': autoEndVehicleSeconds,
        'autoEndStillRadiusMeters': autoEndStillRadiusMeters,
        'autoEndStillSeconds': autoEndStillSeconds,
        'autoEndStillMaxWalkedMeters': autoEndStillMaxWalkedMeters,
      };
}

/// Fields FR2 added (rules version 2). A copy saved by an older app has none of them; `RulesStore.load` fills
/// them from [defaultGameRules] instead of throwing the server's other values away (O10).
const Set<String> fieldsAddedInVersion2 = {
  'minLoopAreaSquareMeters',
  'autoEndVehicleSpeedMetersPerSecond',
  'autoEndVehicleSeconds',
  'autoEndStillRadiusMeters',
  'autoEndStillSeconds',
  'autoEndStillMaxWalkedMeters',
};

/// Built-in copy used only until the app has ever received rules from the server — e.g. the
/// very first launch with no internet. Must match `GameRules` version 2 in
/// api/MyLoop.Api/appsettings.json; a test fails if they drift.
const GameRules defaultGameRules = GameRules(
  version: 2,
  loopClosureDistanceMeters: 50,
  minLoopPoints: 20,
  loopSkipNeighbors: 10,
  gpsAccuracyThresholdMeters: 50,
  minLoopAreaSquareMeters: 5000,
  autoEndVehicleSpeedMetersPerSecond: 9.73,
  autoEndVehicleSeconds: 180,
  autoEndStillRadiusMeters: 75,
  autoEndStillSeconds: 600,
  autoEndStillMaxWalkedMeters: 250,
);
