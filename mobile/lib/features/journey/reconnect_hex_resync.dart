/// Journey map's resync of the player's own hexes (issue #111).
library;

import 'dart:async';

import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/shared/services/realtime_resync.dart';

const _ownHexesLabel = 'own hexes';

/// Re-fetches the player's own-hex snapshot on every [triggers] event — a hub
/// reconnect **or** an app-foreground resume (see [resyncTriggersProvider]).
///
/// SignalR never replays deltas missed while the socket was down, so a hex
/// stolen during an outage would otherwise keep showing as the player's until
/// Journey is reopened — below zoom 14 own hexes are the only layer drawn and
/// the viewport poll does not load them. Resume matters as much as reconnect:
/// after a long background the automatic reconnect gives up and nothing
/// restarts the hub, so no reconnect event ever arrives. `loadUserOwnHexes`
/// full-replaces the owned set, so a cell the server no longer lists
/// disappears.
///
/// Triggers go through [CoalescingResync], so the resume + reconnect pair iOS
/// often fires together costs one fetch (plus one follow-up for a reconnect
/// that lands mid-fetch), and loads never overlap.
///
/// Repaint rides [HexTerritoryManager.hexRevision] (bumped by the load), not a
/// screen-wide `setState` (#129). Other players' hexes are left to the
/// viewport poll: the service clears hex-feed freshness on reconnect, so
/// `ViewportPollBackoff` forces that poll on its next tick — an extra
/// immediate viewport fetch here would only be repeated by that tick.
StreamSubscription<ResyncTrigger> resyncOwnHexes({
  required Stream<ResyncTrigger> triggers,
  required HexTerritoryManager hexes,
}) {
  final resync = CoalescingResync(hexes.loadUserOwnHexes, label: _ownHexesLabel);
  return triggers.listen(resync.handle);
}
