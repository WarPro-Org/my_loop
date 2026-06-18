/// Game-wide constants for the MyLoop mobile app.
///
/// All magic numbers in one place — makes the code easier to read and tune.
library;

class AppConstants {
  AppConstants._(); // prevent instantiation

  // --- GPS / Location ---
  static const double maxAccuracyMeters = 50.0;
  static const double stationaryNoiseFloorMin = 10.0;
  static const double stationaryNoiseFloorMax = 25.0;
  static const double movingNoiseFloorMin = 5.0;
  static const double movingNoiseFloorMax = 15.0;
  static const double stationarySpeedThreshold = 0.3; // m/s
  static const int gpsDistanceFilterMeters = 5;
  static const int gpsTimeoutSeconds = 15;

  // --- Territory / Claims ---
  static const int minGpsPointsPerClaim = 10;
  static const double minWalkDistanceMeters = 200.0;

  // --- Map / Viewport ---
  /// Offset in degrees for nearby viewport queries (~2.2 km radius)
  static const double nearbyViewportOffset = 0.02;

  /// Offset in degrees for wide preload queries (~5.5 km radius)
  static const double wideViewportOffset = 0.05;

  // --- Timer ---
  static const int timerIntervalSeconds = 1;

  // --- Hex refresh ---
  static const int hexRefreshIntervalSeconds = 30;
  static const int maxCachedCells = 1000;

  // --- Preview ---
  static const int maxPreviewPathPoints = 500;

  // --- Celebration ---
  static const int celebrationDelayMs = 800;

  // --- Connectivity ---
  /// Timeout for the pre-journey server reachability probe. Kept short so the
  /// offline gate fails fast instead of waiting out the full request timeout.
  static const int serverReachabilityTimeoutSeconds = 5;

  /// Shown when a user tries to start a journey with no server connection.
  /// Hex capture is server-validated (anti-cheat + claim authority), so there
  /// is nothing to start offline — see issue #35.
  static const String offlineStartJourneyMessage =
      'No internet connection. You need to be online to start a journey and capture hexes.';
}
