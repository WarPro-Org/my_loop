/// Local cache of the signed-in player's block list (DR-002b, #190).
///
/// Blocking only helps if it survives an offline cold start: without this, a blocked player's
/// name would reappear on the cached map/leaderboard until the API is reachable again. Bound to
/// the server user id (cross-user guard) and cleared on sign-out / account deletion, mirroring
/// TerritoryCache.
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _log = Logger('BlockListCache');

class BlockListCache {
  BlockListCache._();

  static const _fileName = 'block_list_cache.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Serializes [userId]'s block list. Pure.
  static String encode(String userId, Set<String> blockedIds) => jsonEncode({
        'userId': userId,
        'blockedUserIds': blockedIds.toList(),
      });

  /// The cached block list for [forUserId], or `null` if [raw] is unparseable, unbound, or
  /// belongs to a different user. Pure.
  static Set<String>? decode(String raw, String forUserId) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['userId'] != forUserId) return null;
      final ids = json['blockedUserIds'] as List?;
      return ids?.cast<String>().toSet();
    } catch (e) {
      _log.warning('Failed to decode cached block list', e);
      return null;
    }
  }

  /// Best-effort write; never throws. An empty [userId] is never cached.
  static Future<void> save(String userId, Set<String> blockedIds) async {
    if (userId.isEmpty) return;
    try {
      final file = await _file();
      await file.writeAsString(encode(userId, blockedIds), flush: true);
    } catch (e, s) {
      _log.warning('Failed to write block list cache', e, s);
    }
  }

  /// The last cached block list for [userId], or `null`.
  static Future<Set<String>?> load(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return decode(await file.readAsString(), userId);
    } catch (e, s) {
      _log.warning('Failed to read block list cache', e, s);
      return null;
    }
  }

  /// Removes the cache so the next account on this device starts clean.
  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e, s) {
      _log.warning('Failed to clear block list cache', e, s);
    }
  }
}
