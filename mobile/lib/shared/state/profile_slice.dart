/// Profile state slice — hex count, streak, distance, rank.
/// Updated via SignalR UserStatsDelta push or full hydration on login.
/// The sole owner of these stats (#113); cleared by invalidating the provider
/// on sign-out / account deletion.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

final _log = Logger('ProfileSlice');

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
    final sub = realtime.onUserStats.listen((delta) {
      _log.fine('Delta received: hexCount=${delta.hexCount}');
      state = state.copyWith(
        hexCount: delta.hexCount,
        totalHexesCaptured: delta.totalHexesCaptured,
        totalHexesStolen: delta.totalHexesStolen,
        streak: delta.streak,
        isStreakActive: delta.isStreakActive,
        distanceKm: delta.distanceKm,
      );
    });
    ref.onDispose(sub.cancel);
    return const ProfileState();
  }

  /// Full hydration from game-state endpoint (login / app resume / post-walk).
  ///
  /// A missing or non-positive `rank` keeps the current rank instead of
  /// zeroing it: game-state reports 0 when its rank query failed, and the
  /// Home tile should keep the last live rank rather than drop to "—" (#171).
  void hydrate(Map<String, dynamic> data) {
    final rank = data['rank'] as int? ?? 0;
    applyStats(
      hexCount: data['hexCount'] as int? ?? 0,
      totalHexesCaptured: data['totalHexesCaptured'] as int? ?? 0,
      totalHexesStolen: data['totalHexesStolen'] as int? ?? 0,
      streak: data['streak'] as int? ?? 0,
      isStreakActive: data['isStreakActive'] as bool? ?? false,
      distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
      rank: rank > 0 ? rank : null,
    );
  }

  /// Sets the given stat fields and marks the slice loaded — the typed
  /// counterpart to [hydrate] for callers that already have parsed values
  /// (e.g. seeding from a freshly fetched `User`, or restoring from
  /// `ProfileCache` while offline) rather than a raw game-state JSON map.
  ///
  /// A `null` argument keeps the field's current value, so a caller that only
  /// knows some stats (a `User` carries no totals, streak flag or rank) never
  /// zeroes the ones it didn't pass.
  void applyStats({
    int? hexCount,
    int? totalHexesCaptured,
    int? totalHexesStolen,
    int? streak,
    bool? isStreakActive,
    double? distanceKm,
    int? rank,
  }) {
    state = state.copyWith(
      hexCount: hexCount,
      totalHexesCaptured: totalHexesCaptured,
      totalHexesStolen: totalHexesStolen,
      streak: streak,
      isStreakActive: isStreakActive,
      distanceKm: distanceKm,
      rank: rank,
      isLoaded: true,
    );
  }

  /// Overwrites only the rank (rank is not pushed via SignalR).
  void updateRank(int newRank) {
    state = state.copyWith(rank: newRank);
  }
}

final profileSliceProvider = NotifierProvider<ProfileSlice, ProfileState>(ProfileSlice.new);
