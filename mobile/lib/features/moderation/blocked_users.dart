/// Player blocking (DR-002b, #190; App Store Guideline 1.2).
///
/// Blocking masks a player's identity for the blocker only — leaderboard, map popups and their
/// profile show [blockedPlayerLabel]. It never affects gameplay.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/block_list_cache.dart';
import 'package:myloop/shared/services/user_state.dart';

final _log = Logger('BlockedUsers');

const blockedPlayerLabel = 'Blocked player';
const blockOfflineError = "You're offline — connect to change who you block";
const blockFailedError = "Couldn't update your block list — try again";
const blockedConfirmation = 'Player blocked — their name is hidden for you';
const unblockedConfirmation = 'Player unblocked';

/// The name to show for [userId]: [blockedPlayerLabel] when blocked, otherwise [name]. Pure.
String displayNameFor(Set<String> blocked, String userId, String name) =>
    blocked.contains(userId) ? blockedPlayerLabel : name;

/// Ids the signed-in player has blocked. Starts from the user-bound cache, then the API.
final blockedUsersProvider = NotifierProvider<BlockedUsersNotifier, Set<String>>(BlockedUsersNotifier.new);

class BlockedUsersNotifier extends Notifier<Set<String>> {
  /// This session's block/unblock decisions (id → blocked), applied on top of every list that
  /// arrives from the cache or the API. A fetch that started before an edit returns the server's
  /// old list; overlaying keeps both the server's existing blocks and the new edit (#195 review).
  final Map<String, bool> _edits = {};

  @override
  Set<String> build() {
    _edits.clear(); // edits belong to the account that made them
    // Rebuild (and reload) only when the signed-in account changes, not on every stat update.
    final userId = ref.watch(userProfileProvider.select((p) => p.userId));
    if (userId == null || userId.isEmpty) return const {};
    // Deliberately not awaited: build() must return synchronously; _load sets state when done.
    unawaited(_load(userId));
    return const {};
  }

  Set<String> _withEdits(Set<String> base) {
    final result = {...base};
    _edits.forEach((id, blocked) => blocked ? result.add(id) : result.remove(id));
    return result;
  }

  Future<void> _load(String userId) async {
    final cached = await BlockListCache.load(userId);
    if (!ref.mounted) return;
    if (cached != null) state = _withEdits(cached);
    try {
      final fresh = await ref.read(apiServiceProvider).getBlockedUserIds();
      if (!ref.mounted) return;
      state = _withEdits(fresh);
      await BlockListCache.save(userId, state);
    } catch (e, s) {
      // Offline: the cached list stays in force. Anything else is a real failure worth logging.
      if (!isServerUnreachable(e)) _log.warning('Failed to load block list', e, s);
    }
  }

  /// Blocks [userId]. Masking applies immediately and is rolled back if the API refuses.
  /// Returns null on success, or a message to show.
  Future<String?> block(String userId) => _update(userId, blocking: true);

  /// Unblocks [userId]; same contract as [block].
  Future<String?> unblock(String userId) => _update(userId, blocking: false);

  Future<String?> _update(String userId, {required bool blocking}) async {
    final owner = ref.read(userProfileProvider).userId;
    final api = ref.read(apiServiceProvider);
    _edits[userId] = blocking;
    state = _withEdits(state);
    try {
      blocking ? await api.blockUser(userId) : await api.unblockUser(userId);
    } catch (e, s) {
      // Roll back only this id: another block made meanwhile may already have succeeded.
      if (ref.mounted) {
        _edits.remove(userId);
        state = blocking ? ({...state}..remove(userId)) : {...state, userId};
      }
      if (isServerUnreachable(e)) return blockOfflineError;
      final serverReason = ApiService.clientErrorReason(e);
      if (serverReason == null) _log.warning('Block update failed unexpectedly', e, s);
      return serverReason ?? blockFailedError;
    }
    // Signed out while the request was in flight: nothing left to update.
    if (!ref.mounted || owner == null) return null;
    await BlockListCache.save(owner, state);
    return null;
  }
}
