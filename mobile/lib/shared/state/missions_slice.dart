/// Missions state slice — daily missions with progress.
/// Updated via SignalR MissionDelta push or full hydration on login.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/models/daily_mission.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

class MissionsState {
  final List<DailyMission> missions;
  final bool allComplete;
  final bool isLoaded;

  const MissionsState({
    this.missions = const [],
    this.allComplete = false,
    this.isLoaded = false,
  });
}

class MissionsSlice extends Notifier<MissionsState> {
  @override
  MissionsState build() {
    final realtime = ref.read(territoryRealtimeProvider);
    realtime.onMissions.listen((delta) {
      debugPrint('[MissionsSlice] Delta received: ${delta.updates.length} updates');
      // Apply progress from delta to existing missions
      final updated = state.missions.map((m) {
        final match = delta.updates.where(
          (u) => u.missionId == m.id,
        );
        if (match.isNotEmpty) {
          final u = match.first;
          return m.copyWith(
            currentProgress: u.currentProgress,
            isCompleted: u.completed,
          );
        }
        return m;
      }).toList();

      state = MissionsState(
        missions: updated,
        allComplete: delta.allMissionsComplete || updated.every((m) => m.completed),
        isLoaded: true,
      );
    });
    return const MissionsState();
  }

  /// Full hydration from game-state endpoint.
  void hydrate(List<dynamic> raw) {
    final missions = raw
        .map((m) => DailyMission.fromJson(m as Map<String, dynamic>))
        .toList();
    state = MissionsState(
      missions: missions,
      allComplete: missions.isNotEmpty && missions.every((m) => m.completed),
      isLoaded: true,
    );
  }
}

final missionsSliceProvider = NotifierProvider<MissionsSlice, MissionsState>(MissionsSlice.new);
