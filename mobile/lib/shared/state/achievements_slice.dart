/// Achievements state slice — unlocked achievements list.
/// Updated via SignalR AchievementUnlocked push or full hydration on login.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/models/achievement.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

final _log = Logger('AchievementsSlice');

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
    final sub = realtime.onAchievements.listen((delta) {
      _log.fine('${delta.unlocks.length} new unlocks');
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
    ref.onDispose(sub.cancel);
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
