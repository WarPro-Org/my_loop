/// Regression tests for issue #129 (ML-ERR-032): while the Journey screen
/// was open, a 30s viewport poll, SignalR deltas, and step-claim integration
/// each ended in a bare `setState(() {})` in `_JourneyMapState` that rebuilt
/// the *entire* map subtree — tile layer, path polyline, HUD, controls — just
/// to repaint hex overlays. GPS is the battery budget's biggest consumer, and
/// a 5s position-refresh `Timer` duplicated the geolocator stream the
/// controller already consumes.
///
/// The fix:
///  1. Hex mutations bump `HexTerritoryManager.hexRevision`; the map wraps
///     only the hex/cooldown layers in a `ValueListenableBuilder` keyed on
///     it, so unrelated layers stop rebuilding on every hex event.
///  2. The periodic viewport poll backs off only when SignalR can account
///     for the unchanged viewport — see `viewport_poll_backoff_test.dart`
///     for that policy; this file covers the service's freshness signal.
///
/// These tests are hermetic — no network, no platform GPS channel, no widget
/// pumping of `JourneyScreen` itself (six other open PRs touch that file;
/// this suite avoids depending on its widget tree shape).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

TerritoryCell _cell(int id, {String ownerId = 'other-user'}) {
  return TerritoryCell(
    cellId: id,
    ownerId: ownerId,
    ownerColor: '#FF0000',
    boundary: const [
      [1.0, 1.0],
      [1.0, 1.001],
      [1.001, 1.001],
      [1.001, 1.0],
    ],
  );
}

/// Serves canned territory responses so the load paths can run hermetically.
class _CannedApi extends ApiService {
  @override
  Future<List<TerritoryCell>> getUserTerritories(String userId) async =>
      [_cell(7, ownerId: userId)];
}

void main() {
  group('HexTerritoryManager.hexRevision (issue #129)', () {
    late HexTerritoryManager manager;

    setUp(() {
      // A plain ApiService is safe to construct here — none of the methods
      // under test touch `_api`, only the pure in-memory mutation paths.
      manager = HexTerritoryManager(api: ApiService(), userId: 'me');
    });

    test('addCapturedHexes bumps the revision', () {
      final before = manager.hexRevision.value;
      manager.addCapturedHexes(const [
        [
          [1.0, 1.0],
          [1.0, 1.001],
          [1.001, 1.001],
        ],
      ]);
      expect(manager.hexRevision.value, before + 1);
    });

    test('updateFromCells (viewport/wide-area load) bumps the revision', () {
      final before = manager.hexRevision.value;
      manager.updateFromCells([_cell(1)]);
      expect(manager.hexRevision.value, before + 1);
    });

    test('integrateStepClaim bumps the revision', () {
      final before = manager.hexRevision.value;
      manager.integrateStepClaim(const [
        [1.0, 1.0],
        [1.0, 1.001],
        [1.001, 1.001],
      ], 42, false);
      expect(manager.hexRevision.value, before + 1);
    });

    test('applyRealtimeChanges bumps only when it changed a known cell', () {
      // Since the #112 keyed store, an event for a cell this client never
      // loaded is a no-op (nothing visible to repaint), so seed the cell.
      manager.updateFromCells([_cell(999)]);
      final before = manager.hexRevision.value;
      expect(manager.applyRealtimeChanges(const []), isFalse);
      expect(manager.hexRevision.value, before, reason: 'no events → no repaint needed');

      final changed = manager.applyRealtimeChanges([
        HexChangeEvent(
          h3Index: '999',
          centerLat: 50.0,
          centerLng: 50.0,
          newOwnerId: 'someone-else',
          newOwnerColor: '#00FF00',
          newOwnerDisplayName: 'Someone',
        ),
      ]);
      expect(changed, isTrue);
      expect(manager.hexRevision.value, before + 1);
    });

    test('loadUserOwnHexes (own-cell replace) bumps the revision', () async {
      final owner = HexTerritoryManager(api: _CannedApi(), userId: 'me');
      final before = owner.hexRevision.value;
      await owner.loadUserOwnHexes();
      expect(owner.userOwnCellIds, {7});
      expect(owner.hexRevision.value, greaterThan(before));
    });

    test('dispose() makes a later mutation a safe no-op instead of throwing', () {
      // An in-flight load* API call can resolve after _JourneyMapState (and
      // this manager) is disposed. Before the fix, that would call
      // ValueNotifier.value= on an already-disposed notifier and throw.
      manager.dispose();
      expect(
        () => manager.addCapturedHexes(const [
          [
            [1.0, 1.0],
            [1.0, 1.001],
            [1.001, 1.001],
          ],
        ]),
        returnsNormally,
      );
    });
  });

  group('TerritoryRealtimeService.timeSinceLastHexEvent (issue #129)', () {
    const hexPayload = [
      [
        {
          'h3Index': '1',
          'centerLat': 1.0,
          'centerLng': 1.0,
          'newOwnerId': 'user-1',
          'newOwnerColor': '#FF0000',
          'newOwnerDisplayName': 'Alice',
        },
      ],
    ];

    TerritoryRealtimeService connectedService() =>
        TerritoryRealtimeService(baseUrl: 'http://test.local')
          ..debugConnected = true;

    test('is null until a hex delta is received', () {
      expect(connectedService().timeSinceLastHexEvent, isNull);
    });

    test('starts a monotonic timer when a HexOwnershipChanged payload arrives', () {
      final service = connectedService()..debugSimulateHexChanges(hexPayload);
      expect(service.timeSinceLastHexEvent, isNotNull);
      expect(service.timeSinceLastHexEvent, lessThan(const Duration(seconds: 1)));
    });

    test('an empty payload does not start it', () {
      final service = connectedService()
        ..debugSimulateHexChanges([<Object?>[]]);
      expect(service.timeSinceLastHexEvent, isNull);
    });

    test('auto-reconnect window: not connected and not fresh', () {
      final service = connectedService()..debugSimulateHexChanges(hexPayload);
      service.debugSimulateReconnecting();
      expect(service.isConnected, isFalse,
          reason: 'withAutomaticReconnect keeps the socket down while retrying');
      expect(service.timeSinceLastHexEvent, isNull);
      // Deltas sent during the outage were lost (#111): even once the socket
      // is back, the pre-outage push must not vouch for the map.
      service.debugConnected = true;
      expect(service.timeSinceLastHexEvent, isNull);
    });

    test('connection close resets freshness', () {
      final service = connectedService()..debugSimulateHexChanges(hexPayload);
      service.debugSimulateClosed();
      service.debugConnected = true;
      expect(service.timeSinceLastHexEvent, isNull);
    });

    test('logout disconnect() resets freshness so the next user starts clean', () async {
      final service = connectedService()..debugSimulateHexChanges(hexPayload);
      await service.disconnect();
      service.debugConnected = true; // next user's session connects
      expect(service.timeSinceLastHexEvent, isNull);
    });
  });
}
