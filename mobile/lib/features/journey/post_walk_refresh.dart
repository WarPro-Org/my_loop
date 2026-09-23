/// Post-walk profile refresh — re-hydrates the game state after a claim and
/// copies the fresh stats into the profile the Home/Map surfaces display.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_rank_sync.dart';
import 'package:myloop/shared/state/profile_slice.dart';

/// Re-hydrates every slice from `GET /api/users/{id}/game-state` and copies the
/// resulting hex count, streak, distance and rank into [userProfileProvider]
/// (which feeds the Home tiles).
///
/// The rank copy is [hydrateAndSyncProfileRank], the same code path sign-in and
/// onboarding use: game-state computes the rank LIVE, whereas the leaderboard
/// endpoint serves the snapshot `LeaderboardRefreshWorker` recomputes only every
/// few minutes (#109), so reading the snapshot right after a claim would
/// overwrite the fresh rank with the pre-walk one. A player with no home city
/// gets their GLOBAL rank from game-state (the same fallback the leaderboard
/// applies). A rank of 0 keeps the current rank.
///
/// When game-state could not be fetched nothing is copied: the slices then hold
/// defaults or pre-walk values, and the profile already has the server's live
/// SignalR stat pushes.
///
/// [isMounted] is checked after the network await so a screen that was closed
/// mid-refresh never touches its disposed `ref`.
Future<void> refreshProfileAfterWalk(
  WidgetRef ref, {
  required bool Function() isMounted,
}) async {
  final applied = await hydrateAndSyncProfileRank(ref, isMounted: isMounted);
  if (!applied) return;

  final gameState = ref.read(profileSliceProvider);
  ref.read(userProfileProvider.notifier).updateStats(
        hexCount: gameState.hexCount,
        streak: gameState.streak,
        distanceKm: gameState.distanceKm,
      );
}
