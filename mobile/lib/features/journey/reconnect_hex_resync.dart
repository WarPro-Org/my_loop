/// Journey map's reconnect resync of the player's own hexes (issue #111).
library;

import 'dart:async';

import 'package:myloop/features/journey/hex_territory_manager.dart';

/// Re-fetches the player's own-hex snapshot every time [onReconnected] fires.
///
/// SignalR never replays deltas missed while the socket was down, so a hex
/// stolen during an outage would otherwise keep showing as the player's until
/// Journey is reopened — below zoom 14 own hexes are the only layer drawn and
/// the viewport poll does not load them. `loadUserOwnHexes` full-replaces the
/// owned set, so a cell the server no longer lists disappears.
///
/// Repaint rides [HexTerritoryManager.hexRevision] (bumped by the load), not a
/// screen-wide `setState` (#129). Other players' hexes are left to the
/// viewport poll: the service clears hex-feed freshness on reconnect, so
/// `ViewportPollBackoff` forces that poll on its next tick — an extra
/// immediate viewport fetch here would only be repeated by that tick.
StreamSubscription<void> resyncOwnHexesOnReconnect({
  required Stream<void> onReconnected,
  required HexTerritoryManager hexes,
}) =>
    onReconnected.listen((_) => hexes.loadUserOwnHexes());
