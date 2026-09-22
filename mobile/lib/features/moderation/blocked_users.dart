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
  /// Bumped by every local block/unblock. A list fetched before an edit is stale and must not
  /// overwrite it (a slow sign-in fetch would otherwise silently undo a block made meanwhile).
  int _localEdits = 0;

  @override
  Set<String> build() {
    // Rebuild (and reload) only when the signed-in account changes, not on every stat update.
    final userId = ref.watch(userProfileProvider.select((p) => p.userId));
    if (userId == null || userId.isEmpty) return const {};
    // Deliberately not awaited: build() must return synchronously; _load sets state when done.
    unawaited(_load(userId));
    return const {};
  }

  Future<void> _load(String userId) async {
    final editsAtStart = _localEdits;
    final cached = await BlockListCache.load(userId);
    // Don't clobber a list the API (or a block tap) already produced.
    if (ref.mounted && cached != null && editsAtStart == _localEdits && state.isEmpty) state = cached;
    try {
      final fresh = await ref.read(apiServiceProvider).getBlockedUserIds();
      if (!ref.mounted || editsAtStart != _localEdits) return;
      state = fresh;
      await BlockListCache.save(userId, fresh);
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
    _localEdits++;
    final previous = state;
    state = blocking ? {...state, userId} : ({...state}..remove(userId));
    final api = ref.read(apiServiceProvider);
    try {
      blocking ? await api.blockUser(userId) : await api.unblockUser(userId);
    } catch (e, s) {
      if (ref.mounted) state = previous;
      if (isServerUnreachable(e)) return blockOfflineError;
      final serverReason = ApiService.extractApiError(e);
      if (serverReason == null) _log.warning('Block update failed unexpectedly', e, s);
      return serverReason ?? blockFailedError;
    }
    final owner = ref.read(userProfileProvider).userId;
    if (owner != null && ref.mounted) await BlockListCache.save(owner, state);
    return null;
  }
}
