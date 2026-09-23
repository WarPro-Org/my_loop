/// Keeps the Home rank tile on game-state's LIVE rank (PR #171 / #109).
///
/// The Home tile reads `userProfileProvider.rank`. Game-state computes that rank
/// live from current hex counts, while the leaderboard endpoint serves a snapshot
/// that `LeaderboardRefreshWorker` rebuilds only every few minutes. So game-state
/// is the single source of the Home rank: sign-in, onboarding and the post-walk
/// refresh all go through [hydrateAndSyncProfileRank].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/profile_cache.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/hydration.dart';
import 'package:myloop/shared/state/profile_slice.dart';

/// Hydrates every slice from game-state, then copies its rank into
/// [userProfileProvider].
///
/// The rank is copied only when hydration reached the server AND the rank is
/// above 0. A failed hydration leaves the slice on defaults (or on an earlier
/// value), and a rank of 0 means game-state had none (its rank query failed), so
/// in both cases the profile keeps its current rank instead of dropping to 0.
///
/// When [cacheForFirebaseUid] is given, the profile is re-saved to
/// [ProfileCache] afterwards, so an offline relaunch restores the live rank
/// rather than whatever was cached before hydration.
///
/// [isMounted] is checked after the network await so a screen closed
/// mid-hydration never touches its disposed `ref`. The profile's user id is
/// checked too: if the user signed out (or switched) while game-state was in
/// flight, nothing is copied or cached, so a signed-out user's cache is never
/// re-created and one user's rank never lands on another's profile.
///
/// Returns whether the live game-state was applied.
Future<bool> hydrateAndSyncProfileRank(
  WidgetRef ref, {
  required bool Function() isMounted,
  String? cacheForFirebaseUid,
}) async {
  final userId = ref.read(userProfileProvider).userId;
  final hydrated = await hydrateAllSlices(ref);
  if (!hydrated || !isMounted()) return false;
  if (ref.read(userProfileProvider).userId != userId) return false;

  final liveRank = ref.read(profileSliceProvider).rank;
  if (liveRank > 0) {
    ref.read(userProfileProvider.notifier).updateStats(rank: liveRank);
  }
  if (cacheForFirebaseUid != null) {
    await ProfileCache.save(cacheForFirebaseUid, ref.read(userProfileProvider));
  }
  return true;
}
