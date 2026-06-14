/// Missions state slice — daily missions with progress.
/// Updated via SignalR MissionDelta push or full hydration on login.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/models/daily_mission.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

final _log = Logger('MissionsSlice');

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
    // Cancel the subscription when the provider is disposed/rebuilt — otherwise
    // every build() re-run (e.g. on logout→login) adds another live listener on
    // the broadcast stream, leaking subscriptions and applying each delta N times.
    final sub = realtime.onMissions.listen((delta) {
      _log.fine('Delta received: ${delta.updates.length} updates');
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
    ref.onDispose(sub.cancel);
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
