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

/// Hydrates all state slices from the unified game-state endpoint.
/// Call this once after login and on app resume from background.
Future<void> hydrateAllSlices(WidgetRef ref) async {
  final api = ref.read(apiServiceProvider);
  final profile = ref.read(userProfileProvider);
  if (profile.userId == null) return;

  final userId = profile.userId!;
  final data = await api.getGameState(userId);
  if (data == null) {
    _log.warning('getGameState returned null — restoring home cards from cache');
    await _restoreOfflineCards(ref, userId);
    return;
  }

  // Fill each slice from the unified response
  ref.read(profileSliceProvider.notifier).hydrate(data);
  ref.read(xpSliceProvider.notifier).hydrate(data);
  ref.read(missionsSliceProvider.notifier).hydrate(data['missions'] as List? ?? []);
  ref.read(achievementsSliceProvider.notifier).hydrate(data['achievements'] as List? ?? []);
  ref.read(explorationSliceProvider.notifier).hydrate(data['exploration'] as List? ?? []);

  await _cacheOfflineCards(userId, data);

  _log.fine('All slices hydrated successfully');
}

/// Same as hydrateAllSlices but accepts a Ref (for use outside widgets).
Future<void> hydrateAllSlicesFromRef(Ref ref) async {
  final api = ref.read(apiServiceProvider);
  final profile = ref.read(userProfileProvider);
  if (profile.userId == null) return;

  final userId = profile.userId!;
  final data = await api.getGameState(userId);
  if (data == null) {
    await _restoreOfflineCardsFromRef(ref, userId);
    return;
  }

  ref.read(profileSliceProvider.notifier).hydrate(data);
  ref.read(xpSliceProvider.notifier).hydrate(data);
  ref.read(missionsSliceProvider.notifier).hydrate(data['missions'] as List? ?? []);
  ref.read(achievementsSliceProvider.notifier).hydrate(data['achievements'] as List? ?? []);
  ref.read(explorationSliceProvider.notifier).hydrate(data['exploration'] as List? ?? []);

  await _cacheOfflineCards(userId, data);
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

/// Offline path for [hydrateAllSlices]: restores the last-known Daily Missions
/// and Area Exploration from the cache when the server is unreachable. Other
/// slices (profile/xp/achievements) are intentionally untouched — profile is
/// restored separately by [ProfileCache], and stale achievements are not part
/// of issue #34.
Future<void> _restoreOfflineCards(WidgetRef ref, String userId) async {
  final cached = await GameStateCache.load(userId);
  if (cached == null) return;
  ref.read(missionsSliceProvider.notifier).hydrate(cached.missions);
  ref.read(explorationSliceProvider.notifier).hydrate(cached.exploration);
  _log.fine('Restored home cards from offline cache');
}

/// [Ref] variant of [_restoreOfflineCards] for use outside widgets.
Future<void> _restoreOfflineCardsFromRef(Ref ref, String userId) async {
  final cached = await GameStateCache.load(userId);
  if (cached == null) return;
  ref.read(missionsSliceProvider.notifier).hydrate(cached.missions);
  ref.read(explorationSliceProvider.notifier).hydrate(cached.exploration);
}
