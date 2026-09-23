/// Keeps the Home rank tile on game-state's LIVE rank (PR #171 / #109).
///
/// The Home tile reads `profileSliceProvider.rank`, the sole owner of game
/// stats (#113). Game-state computes that rank live from current hex counts,
/// while the leaderboard endpoint serves a snapshot that
/// `LeaderboardRefreshWorker` rebuilds only every few minutes. So game-state is
/// the single source of the Home rank: sign-in, onboarding and the post-walk
/// refresh all go through [hydrateAndSyncProfileRank], and nothing writes the
/// leaderboard's `myRank` into the slice.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/profile_cache.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/hydration.dart';
import 'package:myloop/shared/state/profile_slice.dart';

/// Hydrates every slice from game-state, which stores its live rank in
/// [profileSliceProvider].
///
/// The rank changes only when hydration reached the server AND game-state's
/// rank is above 0: a failed hydration leaves the slice untouched, and
/// [ProfileSlice.hydrate] keeps the current rank when game-state reports 0
/// (its rank query failed), so the tile never drops to "—" for either.
///
/// When [cacheForFirebaseUid] is given, the profile and its stats are re-saved
/// to [ProfileCache] afterwards, so an offline relaunch restores the live rank
/// rather than whatever was cached before hydration.
///
/// [isMounted] is checked after the network await so a screen closed
/// mid-hydration never touches its disposed `ref`. The profile's user id is
/// checked too: if the user signed out (or switched) while game-state was in
/// flight, the late response is discarded from the slice and nothing is
/// cached, so a signed-out user's cache is never re-created and one user's
/// stats never land on another's Home.
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
  if (ref.read(userProfileProvider).userId != userId) {
    ref.invalidate(profileSliceProvider);
    return false;
  }

  if (cacheForFirebaseUid != null) {
    await cacheSignedInProfile(ref, cacheForFirebaseUid);
  }
  return true;
}

/// Saves the signed-in identity plus the stats [profileSliceProvider] holds
/// right now to [ProfileCache], bound to [firebaseUid], for offline restore.
Future<void> cacheSignedInProfile(WidgetRef ref, String firebaseUid) {
  final stats = ref.read(profileSliceProvider);
  return ProfileCache.save(
    firebaseUid,
    ref.read(userProfileProvider),
    hexCount: stats.hexCount,
    streak: stats.streak,
    distanceKm: stats.distanceKm,
    rank: stats.rank,
  );
}
