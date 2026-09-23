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

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/state/hydration.dart';

final _log = Logger('RealtimeResync');

const _gameStateLabel = 'game state';

/// Why a resync was requested. The two triggers coalesce differently in
/// [CoalescingResync], so subscribers receive which one fired.
enum ResyncTrigger {
  /// The hub reconnected and has re-joined its groups.
  reconnect,

  /// The app returned to the foreground.
  resume,
}

/// The single "resync now" stream: fires [ResyncTrigger.reconnect] on every
/// hub reconnect and [ResyncTrigger.resume] on every app-foreground resume.
///
/// Every surface that must re-fetch a snapshot after missed deltas subscribes
/// here rather than to [TerritoryRealtimeService.onReconnected] alone. After a
/// long background the automatic reconnect has usually given up, `onclose`
/// fired and nothing restarts the hub, so no reconnect ever arrives. Resume is
/// then the only signal left, and a surface that listened to reconnects only
/// (the Journey map's own hexes did) would keep showing a hex stolen while the
/// app was backgrounded (#111).
///
/// Resume fires whether or not the hub is connected: the snapshots are REST
/// fetches, not SignalR ones.
final resyncTriggersProvider = Provider<Stream<ResyncTrigger>>((ref) {
  final realtime = ref.watch(territoryRealtimeProvider);
  final triggers = StreamController<ResyncTrigger>.broadcast();

  final reconnectSub = realtime.onReconnected
      .listen((_) => triggers.add(ResyncTrigger.reconnect));
  final lifecycleListener = AppLifecycleListener(
    onResume: () => triggers.add(ResyncTrigger.resume),
  );

  ref.onDispose(() {
    reconnectSub.cancel();
    lifecycleListener.dispose();
    triggers.close();
  });
  return triggers.stream;
});

/// Side-effect-only provider: as long as something holds it alive (see
/// [MyLoopApp], which reads it once at the app root) it re-hydrates all game
/// state slices on every [resyncTriggersProvider] event. Hydration already
/// no-ops when signed out and falls back to the offline cache when the server
/// is unreachable. Riverpod only ever runs the build function once per app
/// session, so this is safe to read from multiple places.
final realtimeResyncProvider = Provider<void>((ref) {
  final resync = CoalescingResync(
    () => hydrateAllSlicesFromRef(ref),
    label: _gameStateLabel,
  );
  final sub = ref.watch(resyncTriggersProvider).listen(resync.handle);
  ref.onDispose(sub.cancel);
});

/// Runs one snapshot re-fetch per resync trigger, coalescing triggers that
/// overlap an in-flight fetch. Used for the game-state slices
/// ([realtimeResyncProvider]) and for the Journey map's own hexes.
///
/// On iOS, returning to the foreground often fires a resume and a hub
/// reconnect within moments of each other, so they must not each fetch.
/// But the two triggers are not interchangeable:
///  * a **resume** that lands during a fetch joins it — that fetch already
///    reflects the server state as of now;
///  * a **reconnect** that lands during a fetch queues exactly one follow-up
///    fetch, because the in-flight one may have been served before the user
///    group was re-joined, and deltas pushed in that gap were never delivered.
/// Any number of overlapping triggers therefore costs at most one extra fetch,
/// and fetches never overlap, so an older response can never land after a
/// newer one.
class CoalescingResync {
  CoalescingResync(this._fetch, {required this.label});

  final Future<void> Function() _fetch;

  /// What is being re-fetched, for logs only.
  final String label;

  bool _inFlight = false;
  bool _refetchQueued = false;

  /// Dispatches [trigger] to [onReconnected] or [onResume].
  void handle(ResyncTrigger trigger) => switch (trigger) {
        ResyncTrigger.reconnect => onReconnected(),
        ResyncTrigger.resume => onResume(),
      };

  /// Handles an app-foreground resume.
  void onResume() {
    if (_inFlight) return;
    _log.info('App resumed — re-fetching $label');
    unawaited(_run());
  }

  /// Handles a hub reconnect (groups already re-joined).
  void onReconnected() {
    if (_inFlight) {
      _refetchQueued = true;
      return;
    }
    _log.info('Hub reconnected — re-fetching $label');
    unawaited(_run());
  }

  Future<void> _run() async {
    _inFlight = true;
    try {
      do {
        _refetchQueued = false;
        try {
          await _fetch();
        } catch (e, st) {
          // Nothing awaits this (it runs from a stream/lifecycle callback), so
          // an escaped error would be unhandled; the next trigger retries.
          _log.warning('Resync of $label failed', e, st);
        }
      } while (_refetchQueued);
    } finally {
      _inFlight = false;
    }
  }
}
