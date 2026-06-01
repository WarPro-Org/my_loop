/// Game state hydration — loads all slices from single API call on login/resume.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';
import 'package:myloop/shared/state/xp_slice.dart';
import 'package:myloop/shared/state/missions_slice.dart';
import 'package:myloop/shared/state/achievements_slice.dart';
import 'package:myloop/shared/state/exploration_slice.dart';

/// Hydrates all state slices from the unified game-state endpoint.
/// Call this once after login and on app resume from background.
Future<void> hydrateAllSlices(WidgetRef ref) async {
  final api = ref.read(apiServiceProvider);
  final profile = ref.read(userProfileProvider);
  if (profile.userId == null) return;

  final data = await api.getGameState(profile.userId!);
  if (data == null) {
    debugPrint('[Hydrate] getGameState returned null — skipping hydration');
    return;
  }

  // Fill each slice from the unified response
  ref.read(profileSliceProvider.notifier).hydrate(data);
  ref.read(xpSliceProvider.notifier).hydrate(data);
  ref.read(missionsSliceProvider.notifier).hydrate(data['missions'] as List? ?? []);
  ref.read(achievementsSliceProvider.notifier).hydrate(data['achievements'] as List? ?? []);
  ref.read(explorationSliceProvider.notifier).hydrate(data['exploration'] as List? ?? []);

  debugPrint('[Hydrate] All slices hydrated successfully');
}

/// Same as hydrateAllSlices but accepts a Ref (for use outside widgets).
Future<void> hydrateAllSlicesFromRef(Ref ref) async {
  final api = ref.read(apiServiceProvider);
  final profile = ref.read(userProfileProvider);
  if (profile.userId == null) return;

  final data = await api.getGameState(profile.userId!);
  if (data == null) return;

  ref.read(profileSliceProvider.notifier).hydrate(data);
  ref.read(xpSliceProvider.notifier).hydrate(data);
  ref.read(missionsSliceProvider.notifier).hydrate(data['missions'] as List? ?? []);
  ref.read(achievementsSliceProvider.notifier).hydrate(data['achievements'] as List? ?? []);
  ref.read(explorationSliceProvider.notifier).hydrate(data['exploration'] as List? ?? []);
}
