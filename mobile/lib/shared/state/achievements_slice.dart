/// Achievements state slice — unlocked achievements list.
/// Updated via SignalR AchievementUnlocked push or full hydration on login.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/models/achievement.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

class AchievementsState {
  final List<Achievement> achievements;
  final bool isLoaded;

  const AchievementsState({
    this.achievements = const [],
    this.isLoaded = false,
  });
}

class AchievementsSlice extends Notifier<AchievementsState> {
  @override
  AchievementsState build() {
    final realtime = ref.read(territoryRealtimeProvider);
    realtime.onAchievements.listen((delta) {
      debugPrint('[AchievementsSlice] ${delta.unlocks.length} new unlocks');
      // Mark newly unlocked achievements
      final unlockIds = delta.unlocks.map((u) => u.id).toSet();
      final updated = state.achievements.map((a) {
        if (unlockIds.contains(a.id)) {
          return a.copyWith(unlocked: true);
        }
        return a;
      }).toList();
      state = AchievementsState(achievements: updated, isLoaded: true);
    });
    return const AchievementsState();
  }

  /// Full hydration from game-state endpoint.
  void hydrate(List<dynamic> raw) {
    final achievements = raw
        .map((a) => Achievement.fromJson(a as Map<String, dynamic>))
        .toList();
    state = AchievementsState(achievements: achievements, isLoaded: true);
  }
}

final achievementsSliceProvider =
    NotifierProvider<AchievementsSlice, AchievementsState>(AchievementsSlice.new);
