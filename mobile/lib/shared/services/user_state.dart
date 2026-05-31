/// User state provider — holds current user profile data in memory.
///
/// Manages avatar ID, color, display name, hex count, streak, and stats
/// so that changes immediately reflect across all screens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  UserProfile build() => const UserProfile();

  /// Updates avatar and color together.
  void updateAvatarAndColor(int avatarId, String color) {
    state = state.copyWith(avatarId: avatarId, color: color);
  }

  /// Updates display name.
  void updateDisplayName(String name) {
    state = state.copyWith(displayName: name);
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
