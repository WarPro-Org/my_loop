/// Regression test for PR #171 review round 2, finding 2.
///
/// Since #109 the leaderboard is a snapshot rebuilt every few minutes by
/// `LeaderboardRefreshWorker`, while the Home rank tile gets the LIVE rank from
/// game-state after each walk. `cityLeaderboardProvider` used to copy the
/// snapshot's `myRank` into the rank store (now `profileSliceProvider`, the
/// sole owner of game stats since #113), so merely opening the
/// Leaderboard tab rolled the tile back to the pre-walk rank.
///
/// It FAILS against the pre-fix provider (rank ends up as the snapshot's 5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/leaderboard/leaderboard_screen.dart';
import 'package:myloop/shared/models/leaderboard_entry.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';

const _userId = 'user-1';
const _liveRank = 3;
const _staleSnapshotRank = 5;

/// Serves the un-refreshed snapshot, whose `myRank` is still the pre-walk rank.
class _SnapshotApi extends ApiService {
  _SnapshotApi() : super(baseUrl: 'http://localhost');

  int calls = 0;

  @override
  Future<LeaderboardResponse> getLeaderboard({
    required double lat,
    required double lng,
    String? userId,
    String scope = 'local',
  }) async {
    calls++;
    return const LeaderboardResponse(top: [], myRank: _staleSnapshotRank);
  }
}

void main() {
  test('loading the city leaderboard does not overwrite the live game-state rank', () async {
    final api = _SnapshotApi();
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    // The live rank the post-walk game-state hydration wrote.
    container.read(userProfileProvider.notifier).setFromApi(
          userId: _userId,
          avatarId: 0,
          color: '#000000',
          displayName: 'Player',
        );
    container.read(profileSliceProvider.notifier).applyStats(
          hexCount: 140,
          streak: 4,
          distanceKm: 12.5,
          rank: _liveRank,
        );

    // Keep the autoDispose provider alive while it resolves.
    final sub = container.listen(cityLeaderboardProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(cityLeaderboardProvider.future);

    expect(api.calls, 1);
    expect(container.read(profileSliceProvider).rank, _liveRank);
  });
}
