/// Regression test for issue #139 (D4): `ExplorationSlice.refresh()` sent
/// `lat: 0, lng: 0` query params to `GET /api/territories/exploration/{userId}`
/// that the server never read (`TerritoryService.GetExplorationStats` only
/// ever used `userId`). Both sides now drop the dead params — this test
/// pins `refresh()` to call `getExplorationStats` with only `userId`, and
/// pins the resulting state to what the (param-less) response contains.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/models/exploration_neighborhood.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/exploration_slice.dart';

/// Fake [ApiService] that records how `getExplorationStats` was called and
/// returns a canned response.
class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  int callCount = 0;
  String? lastUserId;

  @override
  Future<List<ExplorationNeighborhood>> getExplorationStats({
    required String userId,
  }) async {
    callCount++;
    lastUserId = userId;
    return [
      const ExplorationNeighborhood(
        neighborhoodId: 42,
        centerLat: 12.34,
        centerLng: 56.78,
        exploredCount: 5,
        ownedCount: 2,
        totalCount: 20,
        percent: 25.0,
        areaName: 'Downtown',
      ),
    ];
  }
}

void main() {
  test(
    'refresh() calls getExplorationStats with only userId (no dead lat/lng)',
    () async {
      final api = _FakeApi();
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      container.read(userProfileProvider.notifier).setFromApi(
            userId: 'user-42',
            avatarId: 0,
            color: '#000000',
            displayName: 'Player',
          );

      await container.read(explorationSliceProvider.notifier).refresh();

      expect(api.callCount, 1);
      expect(api.lastUserId, 'user-42');

      final state = container.read(explorationSliceProvider);
      expect(state.isLoaded, isTrue);
      expect(state.neighborhoods.single.areaName, 'Downtown');
    },
  );

  test('refresh() is a no-op when no user id is set', () async {
    final api = _FakeApi();
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(explorationSliceProvider.notifier).refresh();

    expect(api.callCount, 0);
    expect(container.read(explorationSliceProvider).isLoaded, isFalse);
  });
}
