/// Profile state slice — hex count, streak, distance, rank.
/// Updated via SignalR UserStatsDelta push or full hydration on login.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

class ProfileState {
  final int hexCount;
  final int totalHexesCaptured;
  final int totalHexesStolen;
  final int streak;
  final bool isStreakActive;
  final double distanceKm;
  final int rank;
  final bool isLoaded;

  const ProfileState({
    this.hexCount = 0,
    this.totalHexesCaptured = 0,
    this.totalHexesStolen = 0,
    this.streak = 0,
    this.isStreakActive = false,
    this.distanceKm = 0,
    this.rank = 0,
    this.isLoaded = false,
  });

  ProfileState copyWith({
    int? hexCount,
    int? totalHexesCaptured,
    int? totalHexesStolen,
    int? streak,
    bool? isStreakActive,
    double? distanceKm,
    int? rank,
    bool? isLoaded,
  }) {
    return ProfileState(
      hexCount: hexCount ?? this.hexCount,
      totalHexesCaptured: totalHexesCaptured ?? this.totalHexesCaptured,
      totalHexesStolen: totalHexesStolen ?? this.totalHexesStolen,
      streak: streak ?? this.streak,
      isStreakActive: isStreakActive ?? this.isStreakActive,
      distanceKm: distanceKm ?? this.distanceKm,
      rank: rank ?? this.rank,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class ProfileSlice extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    // Listen to SignalR user stats pushes
    final realtime = ref.read(territoryRealtimeProvider);
    realtime.onUserStats.listen((delta) {
      debugPrint('[ProfileSlice] Delta received: hexCount=${delta.hexCount}');
      state = state.copyWith(
        hexCount: delta.hexCount,
        totalHexesCaptured: delta.totalHexesCaptured,
        totalHexesStolen: delta.totalHexesStolen,
        streak: delta.streak,
        isStreakActive: delta.isStreakActive,
        distanceKm: delta.distanceKm,
      );
    });
    return const ProfileState();
  }

  /// Full hydration from game-state endpoint (login / app resume).
  void hydrate(Map<String, dynamic> data) {
    state = ProfileState(
      hexCount: data['hexCount'] as int? ?? 0,
      totalHexesCaptured: data['totalHexesCaptured'] as int? ?? 0,
      totalHexesStolen: data['totalHexesStolen'] as int? ?? 0,
      streak: data['streak'] as int? ?? 0,
      isStreakActive: data['isStreakActive'] as bool? ?? false,
      distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
      rank: data['rank'] as int? ?? 0,
      isLoaded: true,
    );
  }

  /// Update rank (from leaderboard fetch — not pushed via SignalR).
  void updateRank(int newRank) {
    state = state.copyWith(rank: newRank);
  }
}

final profileSliceProvider = NotifierProvider<ProfileSlice, ProfileState>(ProfileSlice.new);
