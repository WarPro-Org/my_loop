/// Re-synchronizes global game state after a SignalR reconnect or an app
/// foreground resume.
///
/// docs/architecture/realtime.md ("Reconnect & resync — the critical
/// correctness rule") mandates a full snapshot re-fetch on every reconnect,
/// because the hub never replays deltas missed while disconnected. Without
/// this, a player can keep seeing stats/missions/XP from before an outage —
/// or, worst case, believe they still own territory that was actually stolen
/// while they were offline.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/state/hydration.dart';

final _log = Logger('RealtimeResync');

/// Side-effect-only provider: as long as something holds it alive (see
/// [MyLoopApp], which reads it once at the app root) it re-hydrates all game
/// state slices on every hub reconnect and on every app-foreground resume.
/// Riverpod only ever runs the build function once per app session, so this
/// is safe to read from multiple places.
final realtimeResyncProvider = Provider<void>((ref) {
  final realtime = ref.watch(territoryRealtimeProvider);
  final resync = GameStateResync(() => hydrateAllSlicesFromRef(ref));

  final reconnectSub = realtime.onReconnected.listen((_) => resync.onReconnected());

  // Resume re-hydrates whether or not the hub is connected: the snapshot is a
  // REST fetch (GET game-state), not a SignalR one. After a long background
  // the automatic reconnect has usually given up and nothing reconnects the
  // hub, so resume is then the only refresh left. Hydration already no-ops
  // when signed out and falls back to the offline cache when unreachable.
  final lifecycleListener = AppLifecycleListener(onResume: resync.onResume);

  ref.onDispose(() {
    reconnectSub.cancel();
    lifecycleListener.dispose();
  });
});

/// Runs the game-state re-fetch for [realtimeResyncProvider], coalescing
/// triggers that overlap an in-flight fetch.
///
/// On iOS, returning to the foreground often fires a resume and a hub
/// reconnect within moments of each other, so they must not each fetch.
/// But the two triggers are not interchangeable:
///  * a **resume** that lands during a fetch joins it — that fetch already
///    reflects the server state as of now;
///  * a **reconnect** that lands during a fetch queues exactly one follow-up
///    fetch, because the in-flight one may have been served before the user
///    group was re-joined, and deltas pushed in that gap were never delivered.
/// Any number of overlapping triggers therefore costs at most one extra fetch.
class GameStateResync {
  GameStateResync(this._hydrate);

  final Future<void> Function() _hydrate;
  bool _inFlight = false;
  bool _refetchQueued = false;

  /// Handles an app-foreground resume.
  void onResume() {
    if (_inFlight) return;
    _log.info('App resumed — re-hydrating game state');
    _run();
  }

  /// Handles a hub reconnect (groups already re-joined).
  void onReconnected() {
    if (_inFlight) {
      _refetchQueued = true;
      return;
    }
    _log.info('Hub reconnected — re-hydrating game state');
    _run();
  }

  Future<void> _run() async {
    _inFlight = true;
    try {
      do {
        _refetchQueued = false;
        try {
          await _hydrate();
        } catch (e, st) {
          // Nothing awaits this (it runs from a stream/lifecycle callback), so
          // an escaped error would be unhandled; the next trigger retries.
          _log.warning('Game-state resync failed', e, st);
        }
      } while (_refetchQueued);
    } finally {
      _inFlight = false;
    }
  }
}
