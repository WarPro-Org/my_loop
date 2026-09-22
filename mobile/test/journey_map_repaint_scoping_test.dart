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
///  2. The periodic viewport poll backs off while SignalR is connected and
///     has delivered a hex delta recently — `isRealtimePollBackstopRedundant`
///     is the pure decision function, extracted so it's unit-testable
///     without pumping the whole Journey screen and its GPS/API/hydration
///     dependencies.
///
/// These tests are hermetic — no network, no platform GPS channel, no widget
/// pumping of `JourneyScreen` itself (six other open PRs touch that file;
/// this suite avoids depending on its widget tree shape).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/features/journey/journey_screen.dart';
import 'package:myloop/shared/constants/app_constants.dart';
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

    test('applyRealtimeChanges bumps only when the event list is non-empty', () {
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

  group('TerritoryRealtimeService.lastHexEventAt (issue #129)', () {
    test('is null until a hex delta is received', () {
      final service = TerritoryRealtimeService(baseUrl: 'http://test.local');
      expect(service.lastHexEventAt, isNull);
    });

    test('is stamped when a HexOwnershipChanged payload arrives', () {
      final service = TerritoryRealtimeService(baseUrl: 'http://test.local');
      service.debugSimulateHexChanges([
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
      ]);
      expect(service.lastHexEventAt, isNotNull);
      expect(
        DateTime.now().difference(service.lastHexEventAt!),
        lessThan(const Duration(seconds: 1)),
      );
    });

    test('an empty payload does not stamp lastHexEventAt', () {
      final service = TerritoryRealtimeService(baseUrl: 'http://test.local');
      service.debugSimulateHexChanges([<Object?>[]]);
      expect(service.lastHexEventAt, isNull);
    });
  });

  group('isRealtimePollBackstopRedundant (issue #129)', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    test('polls when not connected, regardless of freshness', () {
      expect(
        isRealtimePollBackstopRedundant(isConnected: false, lastEventAt: now, now: now),
        isFalse,
      );
    });

    test('polls when connected but no delta has ever arrived', () {
      expect(
        isRealtimePollBackstopRedundant(isConnected: true, lastEventAt: null, now: now),
        isFalse,
      );
    });

    test('skips when connected and the last delta is within the freshness window', () {
      final lastEvent = now.subtract(
        const Duration(seconds: AppConstants.realtimeFreshnessSeconds - 1),
      );
      expect(
        isRealtimePollBackstopRedundant(isConnected: true, lastEventAt: lastEvent, now: now),
        isTrue,
      );
    });

    test('polls when connected but the last delta is older than the freshness window', () {
      final lastEvent = now.subtract(
        const Duration(seconds: AppConstants.realtimeFreshnessSeconds + 1),
      );
      expect(
        isRealtimePollBackstopRedundant(isConnected: true, lastEventAt: lastEvent, now: now),
        isFalse,
      );
    });
  });
}
