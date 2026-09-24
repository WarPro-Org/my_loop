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
import 'package:myloop/shared/services/realtime_resync.dart';
import 'package:myloop/shared/services/user_state.dart';

final _log = Logger('BlockedUsers');

/// Where a blocked player's name would stand on its own (leaderboard row, map popup, profile):
/// says why the name is hidden, so the viewer can find them again to unblock.
const blockedPlayerLabel = 'Blocked player';

/// A blocked player as the subject of a sentence ("A player captured 3 of your hexes!"). Theft
/// alerts use it in-app and in push (server: `GameConstants.BlockedActorLabel`) so the two copies
/// of one event read the same, and a lock screen never says who was blocked (DR-002b §7.1).
const blockedActorLabel = 'A player';
const blockOfflineError = "You're offline — connect to change who you block";
const blockFailedError = "Couldn't update your block list — try again";
const blockedConfirmation = 'Player blocked — their name is hidden for you';
const unblockedConfirmation = 'Player unblocked';

/// The name to show for [userId]: [blockedPlayerLabel] when blocked, otherwise [name]. Pure.
String displayNameFor(Set<String> blocked, String userId, String name) =>
    blocked.contains(userId) ? blockedPlayerLabel : name;

/// The actor name for a theft alert about [userId]: [blockedActorLabel] when blocked. Pure.
String actorNameFor(Set<String> blocked, String userId, String name) =>
    blocked.contains(userId) ? blockedActorLabel : name;

/// Ids the signed-in player has blocked. Starts from the user-bound cache, then the API.
final blockedUsersProvider = NotifierProvider<BlockedUsersNotifier, Set<String>>(BlockedUsersNotifier.new);

class BlockedUsersNotifier extends Notifier<Set<String>> {
  /// This session's block/unblock decisions (id → blocked), applied on top of every list that
  /// arrives from the cache or the API. A fetch that started before an edit returns the server's
  /// old list; overlaying keeps both the server's existing blocks and the new edit (#195 review).
  final Map<String, bool> _edits = {};

  /// The account this list belongs to; null when signed out.
  String? _userId;

  /// Completes once the first list for [_userId] is known: the cached list, or — with no cache —
  /// the first fetch's outcome, success or failure.
  Completer<void> _firstLoad = Completer<void>();

  /// True once a fetch has succeeded for [_userId]; until then resume/reconnect re-fetch.
  bool _fetched = false;
  bool _fetching = false;

  @override
  Set<String> build() {
    _edits.clear(); // edits belong to the account that made them
    _fetched = false;
    _fetching = false;
    _markLoaded(); // release anyone waiting on the previous account's load
    _firstLoad = Completer<void>();
    // Rebuild (and reload) only when the signed-in account changes, not on every stat update.
    final userId = ref.watch(userProfileProvider.select((p) => p.userId));
    if (userId == null || userId.isEmpty) {
      _userId = null;
      _markLoaded();
      return const {};
    }
    _userId = userId;
    // A load that failed (5xx, or offline with no cache) is retried when the app resumes or the
    // hub reconnects — the triggers every other hydrated slice re-fetches on (#195 review).
    final retry = ref.watch(resyncTriggersProvider).listen((_) {
      if (!_fetched && !_fetching) unawaited(_fetch(userId));
    });
    ref.onDispose(retry.cancel);
    ref.onDispose(_markLoaded);
    // Deliberately not awaited: build() must return synchronously; _load sets state when done.
    unawaited(_load(userId));
    return const {};
  }

  void _markLoaded() {
    if (!_firstLoad.isCompleted) _firstLoad.complete();
  }

  /// [forUserId]'s block list once its first load has settled, or null if the signed-in account
  /// is no longer [forUserId]. For code that records a name for later (theft alerts go to the
  /// persisted inbox): reading [state] right after sign-in would see the empty initial set and
  /// record a blocked player's real name (#195 review). With a cached list the wait is one local
  /// file read.
  Future<Set<String>?> blockedIdsFor(String forUserId) async {
    await _firstLoad.future;
    return ref.mounted && _userId == forUserId ? state : null;
  }

  Set<String> _withEdits(Set<String> base) {
    final result = {...base};
    _edits.forEach((id, blocked) => blocked ? result.add(id) : result.remove(id));
    return result;
  }

  Future<void> _load(String userId) async {
    final cached = await BlockListCache.load(userId);
    if (!ref.mounted) return;
    if (cached != null) {
      state = _withEdits(cached);
      _markLoaded();
    }
    await _fetch(userId);
    _markLoaded();
  }

  Future<void> _fetch(String userId) async {
    _fetching = true;
    try {
      final fresh = await ref.read(apiServiceProvider).getBlockedUserIds();
      if (!ref.mounted) return;
      state = _withEdits(fresh);
      _fetched = true;
      await BlockListCache.save(userId, state);
    } catch (e, s) {
      // Offline: the cached list stays in force. Anything else is a real failure worth logging.
      if (!isServerUnreachable(e)) _log.warning('Failed to load block list', e, s);
    } finally {
      _fetching = false;
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
    // Rollback restores what this id was before, including an earlier successful edit: removing
    // the entry would let an older server list undo that edit (#195 review).
    final previousEdit = _edits[userId];
    final wasBlocked = state.contains(userId);
    _edits[userId] = blocking;
    state = _withEdits(state);
    try {
      blocking ? await api.blockUser(userId) : await api.unblockUser(userId);
    } catch (e, s) {
      // Roll back only this id: another block made meanwhile may already have succeeded.
      if (ref.mounted) {
        previousEdit == null ? _edits.remove(userId) : _edits[userId] = previousEdit;
        final restoreBlocked = previousEdit ?? wasBlocked;
        state = restoreBlocked ? {...state, userId} : ({...state}..remove(userId));
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
