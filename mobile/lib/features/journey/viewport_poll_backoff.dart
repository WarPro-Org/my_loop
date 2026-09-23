/// Decides whether the Journey map's periodic viewport poll may skip a tick
/// (issue #129).
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

/// Returns the time elapsed on a monotonic clock. Injectable so tests can
/// advance time without waiting.
typedef MonotonicClock = Duration Function();

/// Back-off policy for the Journey map's 30s viewport poll.
///
/// The poll is not just a staleness backstop for SignalR: it is the only
/// path that loads the viewport after a pan/zoom, draws hexes this client
/// has never seen (a realtime event carries no boundary), restores cooldowns
/// (events carry none), and subscribes the realtime regions of newly loaded
/// cells. So a tick may only be skipped when live deltas can genuinely
/// account for everything on screen:
///  * the viewport is inside the bounds of the last SUCCESSFUL poll;
///  * the hub is connected and pushed a hex delta within
///    [AppConstants.realtimeFreshnessSeconds] on the current connection;
///  * every region of the loaded cells has a confirmed join;
///  * no realtime event is waiting for a boundary only a load can supply;
///  * the last successful poll is younger than
///    [AppConstants.viewportPollMaxBackoffSeconds] — bounds how long data
///    no delta reports (cooldowns, cells in not-yet-joined regions) can lag.
///
/// Used by `_JourneyMapState._pollViewportHexesIfStale`; the tests drive
/// this exact class with a real [TerritoryRealtimeService] and
/// [HexTerritoryManager].
class ViewportPollBackoff {
  ViewportPollBackoff({MonotonicClock? clock})
      : _clock = clock ?? _stopwatchClock();

  final MonotonicClock _clock;
  LatLngBounds? _lastPolledBounds;
  Duration? _lastPolledAt;

  static MonotonicClock _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// Records that [bounds] were just loaded successfully. Only call this
  /// after a load that actually updated the hex store.
  void recordSuccessfulPoll(LatLngBounds bounds) {
    _lastPolledBounds = bounds;
    _lastPolledAt = _clock();
  }

  /// Whether the tick for [viewport] can be skipped. Any doubt means poll.
  bool shouldSkipTick({
    required LatLngBounds viewport,
    required TerritoryRealtimeService realtime,
    required HexTerritoryManager hexes,
  }) {
    return _viewportCoveredByLastPoll(viewport) &&
        _lastPollRecentEnough() &&
        _hexFeedFresh(realtime) &&
        realtime.isSubscribedToAll(hexes.getActiveRegionIds()) &&
        !hexes.hasUndrawableRealtimeChange;
  }

  bool _viewportCoveredByLastPoll(LatLngBounds viewport) =>
      _lastPolledBounds?.containsBounds(viewport) ?? false;

  bool _lastPollRecentEnough() {
    final polledAt = _lastPolledAt;
    if (polledAt == null) return false;
    return _clock() - polledAt <
        const Duration(seconds: AppConstants.viewportPollMaxBackoffSeconds);
  }

  static bool _hexFeedFresh(TerritoryRealtimeService realtime) {
    final sinceLastEvent = realtime.timeSinceLastHexEvent;
    return sinceLastEvent != null &&
        sinceLastEvent <
            const Duration(seconds: AppConstants.realtimeFreshnessSeconds);
  }
}
