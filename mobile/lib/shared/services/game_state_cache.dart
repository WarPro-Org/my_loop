/// Local cache of the signed-in user's last-known home game-state cards.
///
/// Daily Missions and Area Exploration are loaded once on login/resume from the
/// unified game-state endpoint (`/api/users/{id}/game-state`). That call returns
/// `null` when the device is offline, so previously the missions and exploration
/// slices stayed at their empty defaults and the Home cards showed "no data"
/// even though the user had seen real values moments earlier (issue #34).
///
/// This cache stores the last successfully-hydrated missions + exploration
/// payloads so an offline launch/resume can restore the last-known values. It is
/// written after every successful hydration and cleared on sign-out / account
/// deletion — mirroring the [ProfileCache] offline pattern (issue #19).
///
/// The cache is bound to the server [userId] it was fetched for. Offline restore
/// must verify that binding against the user currently signed in — otherwise a
/// second account on the same device could inherit the first user's missions /
/// exploration while the backend is unreachable (same cross-user guard as #19).
///
/// The payloads are stored as the raw JSON shapes the server returns (the exact
/// lists the slice `hydrate()` methods already consume), so no model
/// serialization is added and the cache is a faithful round-trip of the server
/// response.
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _log = Logger('GameStateCache');

/// The last-known home game-state cards, bound to the [userId] they belong to.
///
/// [missions] and [exploration] hold the raw server JSON lists (each element a
/// `Map<String, dynamic>`), ready to be fed straight back into the missions /
/// exploration slice `hydrate()` methods.
class CachedGameState {
  final String userId;
  final List<dynamic> missions;
  final List<dynamic> exploration;

  const CachedGameState({
    required this.userId,
    required this.missions,
    required this.exploration,
  });
}

/// File-backed store for the last hydrated [CachedGameState]. All methods are
/// static — there is no per-instance state, just JSON in the app documents
/// directory.
class GameStateCache {
  GameStateCache._();

  static const _fileName = 'home_game_state_cache.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Serializes a cached game-state to its JSON string form. Pure —
  /// unit-testable without touching the filesystem.
  static String encode(CachedGameState c) => jsonEncode({
        'userId': c.userId,
        'missions': c.missions,
        'exploration': c.exploration,
      });

  /// Rebuilds a cached game-state from its JSON string form, or `null` if the
  /// payload is missing the server user id or cannot be parsed. The user id is
  /// required so the payload can be safely bound to (and matched against) a
  /// user. Missing missions / exploration default to empty lists. Pure —
  /// unit-testable.
  static CachedGameState? decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final userId = json['userId'] as String?;
      if (userId == null || userId.isEmpty) return null;
      return CachedGameState(
        userId: userId,
        missions: (json['missions'] as List?) ?? const [],
        exploration: (json['exploration'] as List?) ?? const [],
      );
    } catch (e) {
      _log.warning('Failed to decode cached game state', e);
      return null;
    }
  }

  /// Persists the [missions] and [exploration] payloads bound to [userId] so a
  /// later offline launch/resume can restore them. An empty [userId] is never
  /// cached — there would be no user to safely bind the payload to.
  static Future<void> save(
    String userId,
    List<dynamic> missions,
    List<dynamic> exploration,
  ) async {
    if (userId.isEmpty) return;
    try {
      final file = await _file();
      final cached = CachedGameState(
        userId: userId,
        missions: missions,
        exploration: exploration,
      );
      await file.writeAsString(encode(cached), flush: true);
    } catch (e, s) {
      _log.warning('Failed to write game state cache', e, s);
    }
  }

  /// Loads the cached game-state for [userId], or `null` if none exists, it is
  /// unreadable, or it belongs to a different user (cross-user guard). The
  /// user-id match is what makes offline restore safe across accounts on a
  /// shared device.
  static Future<CachedGameState?> load(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final cached = decode(await file.readAsString());
      if (cached == null || cached.userId != userId) return null;
      return cached;
    } catch (e, s) {
      _log.warning('Failed to read game state cache', e, s);
      return null;
    }
  }

  /// Removes the cached game-state. Called on sign-out / account deletion so the
  /// next user does not inherit the previous user's home cards.
  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e, s) {
      _log.warning('Failed to clear game state cache', e, s);
    }
  }
}
