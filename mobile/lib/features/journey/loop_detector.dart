/// Loop detection algorithm — mirrors the backend's ExtractLoops logic.
///
/// Detects closed sub-paths in a GPS trail by finding points
/// that are spatially close to earlier points (within [closureThresholdMeters]).
library;

import 'package:geolocator/geolocator.dart';

class LoopDetector {
  LoopDetector._();

  /// Minimum GPS points required for a meaningful loop.
  static const int minLoopPoints = 20;

  /// Skip this many immediate neighbors to avoid false positives from GPS jitter.
  static const int skipNeighbors = 10;

  /// Maximum distance (meters) between two points to consider a loop closed.
  static const double closureThresholdMeters = 50.0;

  /// A fast, proximity-only estimate of how many closed loops the path has,
  /// used as a live trigger/indicator during a walk. It detects closure
  /// (a point near an earlier non-adjacent point) but does NOT area-validate or
  /// de-duplicate, so it over-counts out-and-back and revisited paths. The
  /// authoritative count comes from the server preview (area-validated +
  /// de-duplicated) and replaces this once it returns (issue #21).
  static int countLoops(List<List<double>> path) {
    if (path.length < minLoopPoints) return 0;

    int loopCount = 0;
    final used = List.filled(path.length, false);

    for (int i = skipNeighbors; i < path.length; i++) {
      if (used[i]) continue;
      for (int j = 0; j <= i - minLoopPoints; j++) {
        if (used[j]) continue;
        final dist = Geolocator.distanceBetween(
          path[i][0], path[i][1],
          path[j][0], path[j][1],
        );
        if (dist <= closureThresholdMeters) {
          loopCount++;
          for (int k = j; k <= i; k++) {
            used[k] = true;
          }
          break;
        }
      }
    }

    // Check simple start≈end case
    if (loopCount == 0 && path.length >= minLoopPoints) {
      final dist = Geolocator.distanceBetween(
        path.first[0], path.first[1],
        path.last[0], path.last[1],
      );
      if (dist <= closureThresholdMeters) loopCount = 1;
    }

    return loopCount;
  }
}
