/// Game rules the app uses (FR1). The server owns them (`GameRules` in appsettings.json) and
/// sends this app-safe subset from `GET /api/rules`; anti-cheat numbers never reach the app.
///
/// Mirrors `ClientRules` in api/MyLoop.Modules.Rules/ClientRules.cs — keep field names in sync.
library;

class GameRules {
  final int version;
  final double loopClosureDistanceMeters;
  final int minLoopPoints;
  final int loopSkipNeighbors;
  final double gpsAccuracyThresholdMeters;

  const GameRules({
    required this.version,
    required this.loopClosureDistanceMeters,
    required this.minLoopPoints,
    required this.loopSkipNeighbors,
    required this.gpsAccuracyThresholdMeters,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'loopClosureDistanceMeters': loopClosureDistanceMeters,
        'minLoopPoints': minLoopPoints,
        'loopSkipNeighbors': loopSkipNeighbors,
        'gpsAccuracyThresholdMeters': gpsAccuracyThresholdMeters,
      };
}

/// Built-in copy used only until the app has ever received rules from the server — e.g. the
/// very first launch with no internet. Must match `GameRules` version 1 in
/// api/MyLoop.Api/appsettings.json; a test fails if they drift.
const GameRules defaultGameRules = GameRules(
  version: 1,
  loopClosureDistanceMeters: 50,
  minLoopPoints: 20,
  loopSkipNeighbors: 10,
  gpsAccuracyThresholdMeters: 50,
);
