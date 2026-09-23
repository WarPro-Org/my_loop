/// Regression test for issue #139 (D9): `joinRegion` used to add the region
/// id to `_subscribedRegions` before the hub `invoke('JoinRegion', ...)`
/// call succeeded. A failed invoke (dropped connection, hub rejection, etc.)
/// still left the region marked as subscribed, so `updateRegions` — which
/// skips regions already in the subscribed set — never retried the join on
/// the next viewport update. The client believed it was receiving live
/// updates for a region the server never actually joined it to.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

/// Fake realtime service whose [invokeJoinRegion] can be made to fail without
/// a live SignalR connection.
class _FlakyJoinRealtime extends TerritoryRealtimeService {
  _FlakyJoinRealtime() : super(baseUrl: 'http://test.local');

  int joinInvokeCalls = 0;
  bool shouldFail = true;

  @override
  Future<void> invokeJoinRegion(String regionId) async {
    joinInvokeCalls++;
    if (shouldFail) {
      throw Exception('simulated JoinRegion invoke failure');
    }
  }
}

void main() {
  const regionId = '872830829ffffff';

  test(
    'a failed JoinRegion invoke does not mark the region subscribed (#139 D9)',
    () async {
      final service = _FlakyJoinRealtime()..debugConnected = true;

      await expectLater(() => service.joinRegion(regionId), throwsException);

      expect(
        service.subscribedRegionsForTest,
        isEmpty,
        reason: 'a failed invoke must not leave the region marked subscribed',
      );
      expect(service.joinInvokeCalls, 1);
    },
  );

  test(
    'updateRegions retries a region whose previous join failed (#139 D9)',
    () async {
      final service = _FlakyJoinRealtime()..debugConnected = true;

      // First viewport update: the invoke fails, so `updateRegions` — which
      // does not swallow errors from `joinRegion` — rejects too. Pre-fix,
      // the region would still have been added to `_subscribedRegions`
      // before that rejection, so the retry below would never re-invoke
      // JoinRegion.
      await expectLater(() => service.updateRegions({regionId}), throwsException);
      expect(service.subscribedRegionsForTest, isEmpty);
      expect(service.joinInvokeCalls, 1);

      // Second viewport update covers the same region — the hub call now
      // succeeds, and the client must actually retry it.
      service.shouldFail = false;
      await service.updateRegions({regionId});

      expect(service.subscribedRegionsForTest, {regionId});
      expect(
        service.joinInvokeCalls,
        2,
        reason: 'updateRegions must retry a region left unsubscribed by a prior failed join',
      );
    },
  );
}
