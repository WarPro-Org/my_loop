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

  // --- Player identity ---
  /// Display-name length bounds — must match GameConstants.Min/MaxDisplayNameLength (API).
  static const int minDisplayNameLength = 2;
  static const int maxDisplayNameLength = 20;

  /// Support address for the in-app "Contact support" row (App Store Guideline 1.2 requires
  /// published contact information). Supplied at build time so it never lives in the repo:
  /// `flutter build ipa --dart-define=SUPPORT_EMAIL=...`. Empty = the row is shown disabled.
  static const String supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

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

  /// While a live SignalR hex delta arrived more recently than this, the
  /// periodic viewport poll is redundant — the push is the freshness source
  /// of truth and the poll only exists as a reconnect/staleness backstop
  /// (issue #129).
  static const int realtimeFreshnessSeconds = 60;

  /// Upper bound on how long the viewport-poll back-off may keep skipping
  /// (#129). Hex deltas carry no cooldown and can't reach regions this client
  /// hasn't joined, so even a fresh feed can't keep the map correct forever;
  /// this caps that lag at a few poll intervals.
  static const int viewportPollMaxBackoffSeconds = 120;

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

  // --- Ending a session (#110) ---
  /// Shown when the server could not delete the account. The user stays signed
  /// in, so they are never told the account is gone while the server keeps it
  /// (App Store Guideline 5.1.1(v)).
  static const String deleteAccountFailedMessage =
      "Couldn't delete your account — try again.";

  /// Shown when the Google/Firebase sign-out throws after the app's own
  /// session state was already cleared.
  static const String signOutFailedMessage =
      "Couldn't finish signing out — try again.";

  /// Screen-reader labels for the modal progress barrier shown while sign-out
  /// or account deletion tears the session down.
  static const String signingOutLabel = 'Signing out';
  static const String deletingAccountLabel = 'Deleting account';

  // --- Offline messaging (issue #36) ---
  // Shown when a modal/screen cannot reach the backend, so the user sees an
  // explicit "you're offline" state instead of a misleading empty/zero one.
  static const String offlineNoticeTitle = "You're offline";
  static const String offlineWalkHistoryMessage =
      'Connect to the internet to load your walk history.';
  static const String offlineRankingMessage =
      'Connect to the internet to see your country and world ranking.';

  /// Label for the in-place retry control shown on offline notices, so the
  /// user can recover once connectivity returns without leaving the screen
  /// (issue #49).
  static const String retryButtonLabel = 'Try again';
}
