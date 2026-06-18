/// User state provider — holds current user profile data in memory.
///
/// Manages avatar ID, color, display name, hex count, streak, and stats
/// so that changes immediately reflect across all screens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

/// Immutable snapshot of the current user's profile.
class UserProfile {
  final String? userId;
  final int avatarId;
  final String color;
  final String displayName;
  final int hexCount;
  final int streak;
  final double distanceKm;
  final int rank;

  const UserProfile({
    this.userId,
    this.avatarId = 0,
    this.color = '#00D4AA',
    this.displayName = 'Player',
    this.hexCount = 0,
    this.streak = 0,
    this.distanceKm = 0,
    this.rank = 0,
  });

  UserProfile copyWith({
    String? userId,
    int? avatarId,
    String? color,
    String? displayName,
    int? hexCount,
    int? streak,
    double? distanceKm,
    int? rank,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      avatarId: avatarId ?? this.avatarId,
      color: color ?? this.color,
      displayName: displayName ?? this.displayName,
      hexCount: hexCount ?? this.hexCount,
      streak: streak ?? this.streak,
      distanceKm: distanceKm ?? this.distanceKm,
      rank: rank ?? this.rank,
    );
  }
}

/// Notifier that manages user profile state.
class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    // Keep the displayed profile in sync with server-authoritative stat pushes.
    // The server emits a UserStatsDelta over SignalR on every capture/steal/victim
    // event (e.g. each batch-step claim while walking). Without consuming it here
    // the hex count shown on the Map and Home stays frozen at its pre-walk value
    // mid-walk and only reconciles after the post-walk refresh — so the Map count
    // diverged from the real (server) count while tracking (issue #30).
    final realtime = ref.read(territoryRealtimeProvider);
    final sub = realtime.onUserStats.listen(_applyStatsDelta);
    ref.onDispose(sub.cancel);
    return const UserProfile();
  }

  /// Applies a live server stat push to the in-memory profile. Only the fields
  /// the delta carries are touched; identity (userId/avatar/color/name) and rank
  /// (sourced from the leaderboard, not pushed here) are preserved.
  void _applyStatsDelta(UserStatsDelta delta) {
    state = state.copyWith(
      hexCount: delta.hexCount,
      streak: delta.streak,
      distanceKm: delta.distanceKm,
    );
  }

  /// Updates avatar and color together.
  void updateAvatarAndColor(int avatarId, String color) {
    state = state.copyWith(avatarId: avatarId, color: color);
    _persistUpdate(avatarId: avatarId, color: color);
  }

  /// Updates display name.
  void updateDisplayName(String name) {
    state = state.copyWith(displayName: name);
    _persistUpdate(displayName: name);
  }

  /// Fire-and-forget API call to persist profile changes.
  void _persistUpdate({String? displayName, int? avatarId, String? color}) {
    final userId = state.userId;
    if (userId == null) return;
    final api = ref.read(apiServiceProvider);
    api.updateUser(userId: userId, displayName: displayName, avatarId: avatarId, color: color);
  }

  /// Updates game stats (from API response).
  void updateStats({int? hexCount, int? streak, double? distanceKm, int? rank}) {
    state = state.copyWith(
      hexCount: hexCount,
      streak: streak,
      distanceKm: distanceKm,
      rank: rank,
    );
  }

  /// Sets the full profile from API data.
  void setFromApi({
    required String userId,
    required int avatarId,
    required String color,
    required String displayName,
    required int hexCount,
    required int streak,
    required double distanceKm,
    int rank = 0,
  }) {
    state = UserProfile(
      userId: userId,
      avatarId: avatarId,
      color: color,
      displayName: displayName,
      hexCount: hexCount,
      streak: streak,
      distanceKm: distanceKm,
      rank: rank,
    );
  }

  /// Resets profile to default (used on sign-out).
  void clear() {
    state = const UserProfile();
  }
}

/// Global user profile provider — watched by profile, home, and avatar widgets.
final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);
