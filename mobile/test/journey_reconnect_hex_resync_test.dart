/// Regression tests for the Journey-map half of issue #111: SignalR never
/// replays hex-ownership deltas missed while the socket was down, so a hex
/// stolen during an outage kept rendering as the player's own until Journey
/// was reopened (below zoom 14 own hexes are the only layer drawn, and the
/// viewport poll never loads them).
///
/// The fix wires `TerritoryRealtimeService.onReconnected` to
/// `HexTerritoryManager.loadUserOwnHexes` via `resyncOwnHexesOnReconnect`,
/// which `_JourneyMapState._subscribeRealtime` uses. Like
/// journey_map_repaint_scoping_test.dart this stays hermetic and does not
/// pump `JourneyScreen`; it drives the real service, the real manager and the
/// exact function the screen subscribes with.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/features/journey/reconnect_hex_resync.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

const _me = 'me';
const _keptCellId = 1;
const _stolenCellId = 2;

TerritoryCell _ownCell(int id) => TerritoryCell(
      cellId: id,
      ownerId: _me,
      ownerColor: '#FF0000',
      boundary: const [
        [1.0, 1.0],
        [1.0, 1.001],
        [1.001, 1.001],
      ],
    );

/// Serves the player's own hexes; [ownedIds] is what the server currently
/// says they own, so a test can "steal" a cell during the outage.
class _OwnHexesApi extends ApiService {
  Set<int> ownedIds = {_keptCellId, _stolenCellId};
  int ownHexFetches = 0;

  @override
  Future<List<TerritoryCell>> getUserTerritories(String userId) async {
    ownHexFetches++;
    return ownedIds.map(_ownCell).toList();
  }
}

void main() {
  late _OwnHexesApi api;
  late HexTerritoryManager hexes;
  late TerritoryRealtimeService realtime;

  setUp(() async {
    api = _OwnHexesApi();
    hexes = HexTerritoryManager(api: api, userId: _me);
    realtime = TerritoryRealtimeService(baseUrl: 'http://test.local');
    await hexes.loadUserOwnHexes();
    api.ownHexFetches = 0;
  });

  tearDown(() {
    hexes.dispose();
    realtime.dispose();
  });

  test('a hex stolen during the outage disappears from the map on reconnect',
      () async {
    expect(hexes.userOwnCellIds, {_keptCellId, _stolenCellId});
    final sub = resyncOwnHexesOnReconnect(
      onReconnected: realtime.onReconnected,
      hexes: hexes,
    );
    addTearDown(sub.cancel);

    // Stolen while the socket was down — the HexOwnershipChanged delta for
    // it was never delivered.
    api.ownedIds = {_keptCellId};
    final revisionBefore = hexes.hexRevision.value;

    await realtime.handleReconnected(connectionId: 'conn-2');
    await pumpEventQueue();

    expect(api.ownHexFetches, 1, reason: 'reconnect must re-fetch own hexes');
    expect(hexes.userOwnCellIds, {_keptCellId});
    expect(hexes.hexRevision.value, greaterThan(revisionBefore),
        reason: 'the map repaints from hexRevision, not a screen setState');
  });

  test('cancelling the subscription (screen disposed) stops the resync',
      () async {
    final sub = resyncOwnHexesOnReconnect(
      onReconnected: realtime.onReconnected,
      hexes: hexes,
    );
    await sub.cancel();

    await realtime.handleReconnected();
    await pumpEventQueue();

    expect(api.ownHexFetches, 0);
  });

  test('reconnect clears hex-feed freshness so the viewport poll runs next tick',
      () async {
    realtime.debugConnected = true;
    realtime.debugSimulateHexChanges(const [
      [
        {
          'h3Index': '1',
          'centerLat': 1.0,
          'centerLng': 1.0,
          'newOwnerId': 'someone',
          'newOwnerColor': '#00FF00',
          'newOwnerDisplayName': 'Someone',
        },
      ],
    ]);
    expect(realtime.timeSinceLastHexEvent, isNotNull);

    await realtime.handleReconnected();

    expect(realtime.isConnected, isTrue);
    expect(realtime.timeSinceLastHexEvent, isNull,
        reason: 'a pre-outage delta must not let ViewportPollBackoff skip the '
            'poll that loads other players\' hexes after a reconnect');
  });
}
