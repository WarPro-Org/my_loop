/// Game-wide constants for the MyLoop mobile app.
///
/// All magic numbers in one place — makes the code easier to read and tune.
library;

class AppConstants {
  AppConstants._(); // prevent instantiation

  // --- GPS / Location ---
  static const double maxAccuracyMeters = 25.0;
  static const double stationaryNoiseFloorMin = 10.0;
  static const double stationaryNoiseFloorMax = 25.0;
  static const double movingNoiseFloorMin = 6.0;
  static const double movingNoiseFloorMax = 20.0;
  static const double stationarySpeedThreshold = 0.3; // m/s
  static const int gpsDistanceFilterMeters = 5;
  static const int gpsTimeoutSeconds = 15;

  // --- Territory / Claims ---
  static const int minGpsPointsPerClaim = 10;
  static const double minWalkDistanceMeters = 200.0;

  // --- Timer ---
  static const int timerIntervalSeconds = 1;
}
