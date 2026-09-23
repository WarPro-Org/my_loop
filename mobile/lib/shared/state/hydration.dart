/// Game state hydration — loads all slices from single API call on login/resume.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/game_state_cache.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';
import 'package:myloop/shared/state/xp_slice.dart';
import 'package:myloop/shared/state/missions_slice.dart';
import 'package:myloop/shared/state/achievements_slice.dart';
import 'package:myloop/shared/state/exploration_slice.dart';

final _log = Logger('Hydrate');

const _logRestoredFromCache =
    'Game state unavailable; restored home cards from offline cache';
const _logNoOfflineCache =
    'Game state unavailable; no offline cache for home cards';

/// Hydrates all state slices from the unified game-state endpoint.
/// Call this once after login and on app resume from background.
///
/// Returns `true` only when the server's game-state was applied; `false` when
/// there was no signed-in user or the call failed (the offline-cache fallback
/// may still have restored some cards). Callers that copy slice values into
/// other state must only do so on `true`, or they would copy defaults.
Future<bool> hydrateAllSlices(WidgetRef ref) => _hydrateAll(
      api: ref.read(apiServiceProvider),
      userId: ref.read(userProfileProvider).userId,
      profile: ref.read(profileSliceProvider.notifier),
      xp: ref.read(xpSliceProvider.notifier),
      missions: ref.read(missionsSliceProvider.notifier),
      achievements: ref.read(achievementsSliceProvider.notifier),
      exploration: ref.read(explorationSliceProvider.notifier),
    );

/// Same as [hydrateAllSlices] but accepts a [Ref], for use outside widgets.
Future<bool> hydrateAllSlicesFromRef(Ref ref) => _hydrateAll(
      api: ref.read(apiServiceProvider),
      userId: ref.read(userProfileProvider).userId,
      profile: ref.read(profileSliceProvider.notifier),
      xp: ref.read(xpSliceProvider.notifier),
      missions: ref.read(missionsSliceProvider.notifier),
      achievements: ref.read(achievementsSliceProvider.notifier),
      exploration: ref.read(explorationSliceProvider.notifier),
    );

/// The single hydration implementation, shared by both entry points above.
///
/// Takes the already-resolved notifiers rather than a Riverpod handle, because
/// `Ref` and `WidgetRef` share no supertype exposing `read`, and the type that
/// would let one function accept either (`ProviderListenable`) is not exported
/// from `flutter_riverpod` — only `ProviderListenableSelect` is. Notifiers, by
/// contrast, are plain classes whichever handle resolved them (#139 D1).
///
/// The two wrappers therefore duplicate only a list of `ref.read` calls, not any
/// logic. That is the part worth having: because every parameter here is
/// `required`, adding a slice and forgetting one wrapper is a **compile error**
/// rather than a silent divergence between the widget and non-widget paths —
/// which is exactly how these two drifted before (the `Ref` variant had lost its
/// logging entirely).
Future<bool> _hydrateAll({
  required ApiService api,
  required String? userId,
  required ProfileSlice profile,
  required XpSlice xp,
  required MissionsSlice missions,
  required AchievementsSlice achievements,
  required ExplorationSlice exploration,
}) async {
  if (userId == null) return false;

  final data = await api.getGameState(userId);
  if (data == null) {
    // INFO, not WARNING: ApiService.getGameState has already logged the
    // failure with its cause, so this line only records what the fallback did.
    final restored = await _restoreOfflineCards(userId, missions, exploration);
    _log.info(restored ? _logRestoredFromCache : _logNoOfflineCache);
    return false;
  }

  // Fill each slice from the unified response
  profile.hydrate(data);
  xp.hydrate(data);
  missions.hydrate(data['missions'] as List? ?? []);
  achievements.hydrate(data['achievements'] as List? ?? []);
  exploration.hydrate(data['exploration'] as List? ?? []);

  await _cacheOfflineCards(userId, data);

  _log.fine('All slices hydrated successfully');
  return true;
}

/// Persists the offline-restorable home cards (Daily Missions + Area
/// Exploration) from a successful game-state response so a later offline
/// launch/resume can show the last-known values (issue #34). Best-effort: a
/// cache write failure never breaks hydration.
Future<void> _cacheOfflineCards(String userId, Map<String, dynamic> data) async {
  await GameStateCache.save(
    userId,
    data['missions'] as List? ?? const [],
    data['exploration'] as List? ?? const [],
  );
}

/// Offline path: restores the last-known Daily Missions and Area Exploration
/// from the cache when the server is unreachable. Other slices (profile/xp/
/// achievements) are intentionally untouched — profile is restored separately by
/// [ProfileCache], and stale achievements are not part of issue #34.
///
/// Returns whether a cache for [userId] existed and was applied, so the caller
/// can log the outcome accurately.
Future<bool> _restoreOfflineCards(
  String userId,
  MissionsSlice missions,
  ExplorationSlice exploration,
) async {
  final cached = await GameStateCache.load(userId);
  if (cached == null) return false;
  missions.hydrate(cached.missions);
  exploration.hydrate(cached.exploration);
  return true;
}
