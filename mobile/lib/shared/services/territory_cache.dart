/// Local cache of the signed-in user's own claimed hexes (territories).
///
/// The Start Journey map loads the user's pre-occupied hexes via
/// [ApiService.getUserTerritories]. When the device is offline that call fails
/// and the map showed none of the user's own hexes (issue #33). This cache
/// stores the last successfully fetched set so the same hexes can render
/// offline, mirroring the offline-profile pattern in [ProfileCache] (issue #19).
///
/// Like the profile cache, the stored set is bound to the [userId] it was
/// fetched for and only restored for that same user — a second account on the
/// same device must never inherit the first user's territory while the backend
/// is unreachable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myloop/shared/models/territory_cell.dart';

final _log = Logger('TerritoryCache');

/// File-backed store for the last fetched set of a single user's own hexes.
/// All methods are static — there is no per-instance state, just JSON in the
/// app documents directory.
class TerritoryCache {
  TerritoryCache._();

  static const _fileName = 'territory_cache.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Serializes [userId]'s [cells] to their JSON string form. Pure —
  /// unit-testable without touching the filesystem.
  static String encode(String userId, List<TerritoryCell> cells) => jsonEncode({
        'userId': userId,
        'cells': cells.map((c) => c.toJson()).toList(),
      });

  /// Rebuilds the cached cells for [forUserId] from [raw], or `null` if the
  /// payload is unparseable, has no bound user id, or belongs to a *different*
  /// user (cross-user guard — never show another account's territory). Pure.
  static List<TerritoryCell>? decode(String raw, String forUserId) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedUserId = json['userId'] as String?;
      if (cachedUserId == null || cachedUserId != forUserId) return null;
      final cells = json['cells'] as List?;
      if (cells == null) return null;
      return cells
          .map((c) => TerritoryCell.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log.warning('Failed to decode cached territories', e);
      return null;
    }
  }

  /// Persists [cells] bound to [userId] so a later offline launch can restore
  /// them. An empty [userId] is never cached — there is nothing to safely bind
  /// the territory to. Failures are swallowed: caching is best-effort.
  static Future<void> save(String userId, List<TerritoryCell> cells) async {
    if (userId.isEmpty) return;
    try {
      final file = await _file();
      await file.writeAsString(encode(userId, cells), flush: true);
    } catch (e, s) {
      _log.warning('Failed to write territory cache', e, s);
    }
  }

  /// Loads the last cached own-hexes for [userId], or `null` if none exists, it
  /// is unreadable, or it belongs to a different user.
  static Future<List<TerritoryCell>?> load(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return decode(await file.readAsString(), userId);
    } catch (e, s) {
      _log.warning('Failed to read territory cache', e, s);
      return null;
    }
  }

  /// Removes the cached territories. Called on sign-out / account deletion so
  /// the next user does not inherit the previous user's hexes.
  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e, s) {
      _log.warning('Failed to clear territory cache', e, s);
    }
  }
}
