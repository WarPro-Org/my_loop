/// Regression tests for the Journey-map half of issue #111: SignalR never
/// replays hex-ownership deltas missed while the socket was down, so a hex
/// stolen during an outage kept rendering as the player's own until Journey
/// was reopened (below zoom 14 own hexes are the only layer drawn, and the
/// viewport poll never loads them).
///
/// The fix wires `resyncTriggersProvider` — one stream fed by hub reconnects
/// **and** app-foreground resumes — to `HexTerritoryManager.loadUserOwnHexes`
/// via `resyncOwnHexes`, which `_JourneyMapState._subscribeRealtime` uses.
/// Resume is essential: after a long background the automatic reconnect gives
/// up and nothing restarts the hub, so no reconnect event ever arrives.
///
/// Like journey_map_repaint_scoping_test.dart this stays hermetic and does not
/// pump `JourneyScreen`; it drives the real service, the real trigger
/// provider, the real manager and the exact function the screen subscribes
/// with.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/features/journey/reconnect_hex_resync.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/realtime_resync.dart';
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

/// Drives a real foreground transition on the shared binding. Going via
/// `inactive` is the only sequence that fires `AppLifecycleListener.onResume`
/// (see realtime_reconnect_resync_test.dart).
void _resumeApp() {
  final binding = TestWidgetsFlutterBinding.instance;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _OwnHexesApi api;
  late HexTerritoryManager hexes;
  late TerritoryRealtimeService realtime;
  late ProviderContainer container;

  setUp(() async {
    // The lifecycle state lives on the process-wide binding, so a previous
    // test leaving it at `resumed` would make the next resume a no-op.
    TestWidgetsFlutterBinding.instance.resetInternalState();
    api = _OwnHexesApi();
    hexes = HexTerritoryManager(api: api, userId: _me);
    realtime = TerritoryRealtimeService(baseUrl: 'http://test.local');
    container = ProviderContainer(overrides: [
      territoryRealtimeProvider.overrideWithValue(realtime),
    ]);
    await hexes.loadUserOwnHexes();
    api.ownHexFetches = 0;
  });

  tearDown(() {
    container.dispose();
    hexes.dispose();
    realtime.dispose();
  });

  /// Subscribes exactly as `_JourneyMapState._subscribeRealtime` does.
  void subscribeLikeJourney() {
    final sub = resyncOwnHexes(
      triggers: container.read(resyncTriggersProvider),
      hexes: hexes,
    );
    addTearDown(sub.cancel);
  }

  test('a hex stolen during the outage disappears from the map on reconnect',
      () async {
    expect(hexes.userOwnCellIds, {_keptCellId, _stolenCellId});
    subscribeLikeJourney();

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

  test('a hex stolen while backgrounded disappears on resume, even though the '
      'hub never reconnects', () async {
    subscribeLikeJourney();
    // Long background: automatic reconnect gave up, so no reconnect event
    // will ever arrive — resume is the only signal.
    expect(realtime.isConnected, isFalse);
    api.ownedIds = {_keptCellId};
    final revisionBefore = hexes.hexRevision.value;

    _resumeApp();
    await pumpEventQueue();

    expect(TestWidgetsFlutterBinding.instance.lifecycleState,
        AppLifecycleState.resumed,
        reason: 'the resume must really have been delivered, or this asserts nothing');
    expect(api.ownHexFetches, 1, reason: 'resume must re-fetch own hexes');
    expect(hexes.userOwnCellIds, {_keptCellId});
    expect(hexes.hexRevision.value, greaterThan(revisionBefore));
  });

  test('cancelling the subscription (screen disposed) stops the resync',
      () async {
    final sub = resyncOwnHexes(
      triggers: container.read(resyncTriggersProvider),
      hexes: hexes,
    );
    await sub.cancel();

    await realtime.handleReconnected();
    _resumeApp();
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
