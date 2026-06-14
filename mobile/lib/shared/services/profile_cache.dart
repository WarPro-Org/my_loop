/// Local cache of the signed-in user's MyLoop profile.
///
/// Firebase Auth already persists the *session* across app restarts, so a
/// returning user is still authenticated without logging in again. What it
/// does NOT persist is the MyLoop profile (server id, display name, stats) —
/// that normally comes from a backend call on launch. When the device is
/// offline at launch that call fails, and previously the user was bounced
/// back to the login screen even though they were still signed in.
///
/// This cache stores the last-known profile so an already-authenticated user
/// can enter the app offline (issue #19). It is written after every successful
/// login/profile fetch and cleared on sign-out.
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myloop/shared/services/user_state.dart';

final _log = Logger('ProfileCache');

/// File-backed store for the last signed-in [UserProfile]. All methods are
/// static — there is no per-instance state, just JSON in the app documents
/// directory.
class ProfileCache {
  ProfileCache._();

  static const _fileName = 'profile_cache.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Serializes a profile to its JSON string form. Pure — unit-testable
  /// without touching the filesystem.
  static String encode(UserProfile p) => jsonEncode({
        'userId': p.userId,
        'avatarId': p.avatarId,
        'color': p.color,
        'displayName': p.displayName,
        'hexCount': p.hexCount,
        'streak': p.streak,
        'distanceKm': p.distanceKm,
        'rank': p.rank,
      });

  /// Rebuilds a profile from its JSON string form, or `null` if the payload is
  /// missing a user id or cannot be parsed. Pure — unit-testable.
  static UserProfile? decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final userId = json['userId'] as String?;
      if (userId == null) return null;
      return UserProfile(
        userId: userId,
        avatarId: (json['avatarId'] as num?)?.toInt() ?? 0,
        color: json['color'] as String? ?? '#00D4AA',
        displayName: json['displayName'] as String? ?? 'Player',
        hexCount: (json['hexCount'] as num?)?.toInt() ?? 0,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      _log.warning('Failed to decode cached profile', e);
      return null;
    }
  }

  /// Persists [profile] so a later offline launch can restore it. A profile
  /// without a server [UserProfile.userId] is never cached — there is nothing
  /// to restore a session from.
  static Future<void> save(UserProfile profile) async {
    if (profile.userId == null) return;
    try {
      final file = await _file();
      await file.writeAsString(encode(profile), flush: true);
    } catch (e, s) {
      _log.warning('Failed to write profile cache', e, s);
    }
  }

  /// Loads the last cached profile, or `null` if none exists / is unreadable.
  static Future<UserProfile?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return decode(await file.readAsString());
    } catch (e, s) {
      _log.warning('Failed to read profile cache', e, s);
      return null;
    }
  }

  /// Removes the cached profile. Called on sign-out / account deletion so the
  /// next user does not inherit the previous session.
  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e, s) {
      _log.warning('Failed to clear profile cache', e, s);
    }
  }
}
