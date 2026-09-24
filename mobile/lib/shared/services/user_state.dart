/// User state provider — holds the current user's identity in memory.
///
/// Manages user id, avatar ID, color, and display name so that identity
/// changes immediately reflect across all screens. Game stats (hex count,
/// streak, distance, rank) are owned exclusively by `profileSliceProvider`
/// (see `shared/state/profile_slice.dart`) — see issue #113: this notifier
/// used to also mirror those stats from live SignalR pushes, which let it
/// drift from the slice under ties/scopes since two independent listeners
/// updated two independent copies of the same numbers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/util/display_name.dart';

final _log = Logger('UserProfile');

/// Immutable snapshot of the current user's identity.
class UserProfile {
  final String? userId;
  final int avatarId;
  final String color;
  final String displayName;

  const UserProfile({
    this.userId,
    this.avatarId = 0,
    this.color = '#00D4AA',
    this.displayName = 'Player',
  });

  UserProfile copyWith({
    String? userId,
    int? avatarId,
    String? color,
    String? displayName,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      avatarId: avatarId ?? this.avatarId,
      color: color ?? this.color,
      displayName: displayName ?? this.displayName,
    );
  }
}

/// Notifier that manages user identity state.
class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() => const UserProfile();

  /// Updates avatar and color together.
  void updateAvatarAndColor(int avatarId, String color) {
    state = state.copyWith(avatarId: avatarId, color: color);
    _persistUpdate(avatarId: avatarId, color: color);
  }

  /// Saves a new display name. Returns null on success, or a message to show the player.
  ///
  /// Waits for the API instead of updating optimistically: the server can refuse a name the
  /// client cannot pre-check (the moderation blocklist, #190), and a fire-and-forget save
  /// would show the new name locally while the server kept the old one.
  Future<String?> updateDisplayName(String name) async {
    final canonical = canonicalDisplayName(name);
    final userId = state.userId;
    if (userId != null) {
      try {
        await ref.read(apiServiceProvider).updateUser(userId: userId, displayName: canonical);
      } catch (e, s) {
        if (isServerUnreachable(e)) return displayNameOfflineError;
        final serverReason = ApiService.clientErrorReason(e);
        // A server reason is an expected refusal; anything else is a real failure worth a log.
        if (serverReason == null) _log.warning('Rename failed unexpectedly', e, s);
        return serverReason ?? displayNameSaveFailedError;
      }
    }
    state = state.copyWith(displayName: canonical);
    return null;
  }

  /// Fire-and-forget API call to persist profile changes.
  void _persistUpdate({String? displayName, int? avatarId, String? color}) {
    final userId = state.userId;
    if (userId == null) return;
    final api = ref.read(apiServiceProvider);
    api.updateUser(userId: userId, displayName: displayName, avatarId: avatarId, color: color);
  }

  /// Sets the full identity from API data.
  void setFromApi({
    required String userId,
    required int avatarId,
    required String color,
    required String displayName,
  }) {
    state = UserProfile(
      userId: userId,
      avatarId: avatarId,
      color: color,
      displayName: displayName,
    );
  }

  /// The signed-in user's id right now, or null once signed out. Lets an
  /// async flow that captured the notifier re-check who is signed in after an
  /// await, without needing a `Ref`/`WidgetRef` that may have been disposed.
  String? get currentUserId => state.userId;

  /// Resets profile to default (used on sign-out).
  void clear() {
    state = const UserProfile();
  }
}

/// Global user profile provider — watched by profile, home, and avatar widgets.
final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);
