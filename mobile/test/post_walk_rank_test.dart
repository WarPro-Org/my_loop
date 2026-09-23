/// Regression test for PR #171 / issue #109 — the post-walk Home rank tile.
///
/// Once `POST /api/leaderboard/refresh` was removed, the leaderboard snapshot is
/// only recomputed by the server's background worker (every few minutes). The
/// post-walk refresh used to re-read that snapshot via `getLeaderboard` and write
/// its `myRank` into the Home rank, overwriting the LIVE rank that game-state
/// hydration had just fetched — so a player who climbed the city board still
/// saw their pre-walk rank. The fix takes the rank from game-state. Since #113
/// the rank lives in `profileSliceProvider` (the sole owner of game stats), so
/// that is what these tests read.
///
/// It FAILS against the pre-fix logic (rank ends up as the stale snapshot's 5).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/post_walk_refresh.dart';
import 'package:myloop/shared/models/leaderboard_entry.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _userId = 'user-1';
const _preWalkRank = 5;
const _liveRank = 3;

/// Hydration persists the offline home cards; point that write at a temp dir.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Game-state reports the live post-claim rank; the leaderboard still serves the
/// un-refreshed snapshot holding the pre-walk rank.
class _FakeApi extends ApiService {
  _FakeApi({required this.gameStateRank}) : super(baseUrl: 'http://localhost');

  final int? gameStateRank;
  int leaderboardCalls = 0;

  @override
  Future<Map<String, dynamic>?> getGameState(String userId) async => {
        'hexCount': 140,
        'streak': 4,
        'distanceKm': 12.5,
        if (gameStateRank != null) 'rank': gameStateRank,
      };

  @override
  Future<LeaderboardResponse> getLeaderboard({
    required double lat,
    required double lng,
    String? userId,
    String scope = 'local',
  }) async {
    leaderboardCalls++;
    return const LeaderboardResponse(top: [], myRank: _preWalkRank);
  }
}

/// Pumps a widget that exposes a real [WidgetRef] from a scope using [api], with
/// the profile set to its pre-walk state.
Future<(WidgetRef, ProviderContainer)> _pumpWithRef(
  WidgetTester tester,
  ApiService api,
) async {
  late WidgetRef captured;
  await tester.pumpWidget(ProviderScope(
    overrides: [apiServiceProvider.overrideWithValue(api)],
    child: Consumer(builder: (context, ref, _) {
      captured = ref;
      return const SizedBox.shrink();
    }),
  ));
  final container = ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
  container.read(userProfileProvider.notifier).setFromApi(
        userId: _userId,
        avatarId: 0,
        color: '#000000',
        displayName: 'Player',
      );
  container.read(profileSliceProvider.notifier).applyStats(
        hexCount: 100,
        streak: 3,
        distanceKm: 10,
        rank: _preWalkRank,
      );
  return (captured, container);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('post_walk_rank_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('post-walk rank comes from game-state, not the stale leaderboard snapshot',
      (tester) async {
    final api = _FakeApi(gameStateRank: _liveRank);
    final (ref, container) = await _pumpWithRef(tester, api);

    await tester.runAsync(() => refreshProfileAfterWalk(ref, isMounted: () => true));

    final stats = container.read(profileSliceProvider);
    expect(stats.rank, _liveRank);
    expect(stats.hexCount, 140);
    expect(api.leaderboardCalls, 0,
        reason: 'the leaderboard snapshot is not refreshed per claim any more (#109)');
  });

  testWidgets('keeps the current rank when game-state has none', (tester) async {
    final api = _FakeApi(gameStateRank: null);
    final (ref, container) = await _pumpWithRef(tester, api);

    await tester.runAsync(() => refreshProfileAfterWalk(ref, isMounted: () => true));

    expect(container.read(profileSliceProvider).rank, _preWalkRank);
  });

  // PR #171 round 2, finding 1. A player who skipped "set home" (or whose reverse
  // geocode failed) has no city. Game-state now ranks them on the global board
  // instead of the bogus #1 an empty-city count produced; the server-side
  // regression test is GameStateCitylessRankTests. This locks the client half of
  // the contract: that global rank reaches the Home tile unchanged.
  testWidgets('a city-less player gets the global rank game-state reports', (tester) async {
    const globalRank = 42;
    final api = _FakeApi(gameStateRank: globalRank);
    final (ref, container) = await _pumpWithRef(tester, api);

    await tester.runAsync(() => refreshProfileAfterWalk(ref, isMounted: () => true));

    expect(container.read(profileSliceProvider).rank, globalRank);
    expect(api.leaderboardCalls, 0);
  });

  testWidgets('an explicit rank of 0 (server rank query failed) keeps the current rank',
      (tester) async {
    final api = _FakeApi(gameStateRank: 0);
    final (ref, container) = await _pumpWithRef(tester, api);

    await tester.runAsync(() => refreshProfileAfterWalk(ref, isMounted: () => true));

    expect(container.read(profileSliceProvider).rank, _preWalkRank);
  });

  // The slice is written by hydration itself, not by the screen, so the fresh
  // stats land even when the screen closed mid-refresh (single owner, #113).
  testWidgets('a screen closed mid-refresh still leaves the fresh stats in the slice',
      (tester) async {
    final api = _FakeApi(gameStateRank: _liveRank);
    final (ref, container) = await _pumpWithRef(tester, api);

    await tester.runAsync(() => refreshProfileAfterWalk(ref, isMounted: () => false));

    final stats = container.read(profileSliceProvider);
    expect(stats.rank, _liveRank);
    expect(stats.hexCount, 140);
  });
}
