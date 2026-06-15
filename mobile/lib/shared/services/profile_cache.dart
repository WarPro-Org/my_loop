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
///
/// The cached profile is bound to the Firebase UID it belongs to. Offline
/// restore must verify that binding against the user Firebase actually has
/// signed in — otherwise a second account on the same device could inherit the
/// first user's profile/session while the backend is unreachable (issue #19
/// review: cross-user identity).
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myloop/shared/services/user_state.dart';

final _log = Logger('ProfileCache');

/// A cached [UserProfile] bound to the [firebaseUid] it was fetched for.
///
/// The binding is what makes offline restore safe: we only restore when this
/// [firebaseUid] matches the user Firebase Auth currently has signed in.
class CachedProfile {
  final String firebaseUid;
  final UserProfile profile;

  const CachedProfile({required this.firebaseUid, required this.profile});
}

/// File-backed store for the last signed-in [CachedProfile]. All methods are
/// static — there is no per-instance state, just JSON in the app documents
/// directory.
class ProfileCache {
  ProfileCache._();

  static const _fileName = 'profile_cache.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Serializes a cached profile to its JSON string form. Pure — unit-testable
  /// without touching the filesystem.
  static String encode(CachedProfile c) => jsonEncode({
        'firebaseUid': c.firebaseUid,
        'userId': c.profile.userId,
        'avatarId': c.profile.avatarId,
        'color': c.profile.color,
        'displayName': c.profile.displayName,
        'hexCount': c.profile.hexCount,
        'streak': c.profile.streak,
        'distanceKm': c.profile.distanceKm,
        'rank': c.profile.rank,
      });

  /// Rebuilds a cached profile from its JSON string form, or `null` if the
  /// payload is missing the Firebase UID or server user id, or cannot be
  /// parsed. Both ids are required: without the UID the profile can't be safely
  /// bound to a user, and without the user id there is no session to restore.
  /// Pure — unit-testable.
  static CachedProfile? decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final firebaseUid = json['firebaseUid'] as String?;
      final userId = json['userId'] as String?;
      if (firebaseUid == null || firebaseUid.isEmpty || userId == null) {
        return null;
      }
      return CachedProfile(
        firebaseUid: firebaseUid,
        profile: UserProfile(
          userId: userId,
          avatarId: (json['avatarId'] as num?)?.toInt() ?? 0,
          color: json['color'] as String? ?? '#00D4AA',
          displayName: json['displayName'] as String? ?? 'Player',
          hexCount: (json['hexCount'] as num?)?.toInt() ?? 0,
          streak: (json['streak'] as num?)?.toInt() ?? 0,
          distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
          rank: (json['rank'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (e) {
      _log.warning('Failed to decode cached profile', e);
      return null;
    }
  }

  /// Persists [profile] bound to [firebaseUid] so a later offline launch can
  /// restore it. A profile without a server [UserProfile.userId], or an empty
  /// [firebaseUid], is never cached — there is nothing to safely restore a
  /// session from.
  static Future<void> save(String firebaseUid, UserProfile profile) async {
    if (firebaseUid.isEmpty || profile.userId == null) return;
    try {
      final file = await _file();
      final cached = CachedProfile(firebaseUid: firebaseUid, profile: profile);
      await file.writeAsString(encode(cached), flush: true);
    } catch (e, s) {
      _log.warning('Failed to write profile cache', e, s);
    }
  }

  /// Loads the last cached profile, or `null` if none exists / is unreadable.
  static Future<CachedProfile?> load() async {
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
