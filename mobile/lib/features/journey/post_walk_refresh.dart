/// Post-walk profile refresh — re-hydrates the game state after a claim and
/// copies the fresh stats into the profile the Home/Map surfaces display.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/hydration.dart';
import 'package:myloop/shared/state/profile_slice.dart';

/// Re-hydrates every slice from `GET /api/users/{id}/game-state` and copies the
/// resulting hex count, streak, distance and city rank into [userProfileProvider]
/// (which feeds the Home rank tile).
///
/// The rank comes from game-state on purpose: that endpoint computes it LIVE from
/// current hex counts, whereas the leaderboard endpoint serves the snapshot that
/// `LeaderboardRefreshWorker` recomputes only every few minutes (#109). Reading the
/// snapshot right after a claim would overwrite the fresh rank with the pre-walk
/// one. A rank of 0 means game-state had none (offline, or no rank yet), so the
/// profile keeps its current rank instead of showing "#0".
///
/// [isMounted] is checked after the network await so a screen that was closed
/// mid-refresh never touches its disposed `ref`.
Future<void> refreshProfileAfterWalk(
  WidgetRef ref, {
  required bool Function() isMounted,
}) async {
  await hydrateAllSlices(ref);
  if (!isMounted()) return;

  final gameState = ref.read(profileSliceProvider);
  final currentRank = ref.read(userProfileProvider).rank;
  ref.read(userProfileProvider.notifier).updateStats(
        hexCount: gameState.hexCount,
        streak: gameState.streak,
        distanceKm: gameState.distanceKm,
        rank: gameState.rank > 0 ? gameState.rank : currentRank,
      );
}
