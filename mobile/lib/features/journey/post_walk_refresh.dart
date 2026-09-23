/// Post-walk profile refresh — re-hydrates the game state after a claim so the
/// Home/Map surfaces show the fresh stats.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/state/profile_rank_sync.dart';

/// Re-hydrates every slice from `GET /api/users/{id}/game-state`. The hex
/// count, streak, distance and rank land in `profileSliceProvider`, the sole
/// owner of game stats (#113), which feeds the Home tiles and the map badge.
///
/// This is [hydrateAndSyncProfileRank], the same code path sign-in and
/// onboarding use: game-state computes the rank LIVE, whereas the leaderboard
/// endpoint serves the snapshot `LeaderboardRefreshWorker` recomputes only every
/// few minutes (#109), so reading the snapshot right after a claim would
/// overwrite the fresh rank with the pre-walk one. A player with no home city
/// gets their GLOBAL rank from game-state (the same fallback the leaderboard
/// applies). A rank of 0 keeps the current rank.
///
/// When game-state could not be fetched the slice keeps its current values,
/// which the server's live SignalR stat pushes already keep current.
///
/// [isMounted] is checked after the network await so a screen that was closed
/// mid-refresh never touches its disposed `ref`.
Future<void> refreshProfileAfterWalk(
  WidgetRef ref, {
  required bool Function() isMounted,
}) async {
  await hydrateAndSyncProfileRank(ref, isMounted: isMounted);
}
