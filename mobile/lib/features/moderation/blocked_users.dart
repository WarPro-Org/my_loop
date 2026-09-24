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

/// How long the map's hex popup waits for the block list's first load before showing the sheet
/// anyway. Past this, another player's name is shown as [blockedActorLabel] rather than risk
/// showing a blocked player's real name (#195 review).
const blockListPopupWait = Duration(seconds: 2);

/// The name to show for [userId]: [blockedPlayerLabel] when blocked, otherwise [name]. Pure.
String displayNameFor(Set<String> blocked, String userId, String name) =>
    blocked.contains(userId) ? blockedPlayerLabel : name;

/// The owner name for the map's hex popup. [blocked] is null when the block list isn't known yet
/// (still loading after [blockListPopupWait]): the viewer's own name is shown, anyone else's is
/// withheld as [blockedActorLabel]. Pure.
String hexOwnerNameFor(Set<String>? blocked, String? viewerId, String ownerId, String name) {
  if (blocked != null) return displayNameFor(blocked, ownerId, name);
  return ownerId == viewerId ? name : blockedActorLabel;
}

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

  /// The edits the server has accepted this session (id → blocked): what a failed edit rolls back
  /// to. With no entry, a failed edit falls back to [_base].
  final Map<String, bool> _confirmed = {};

  /// Per id, the token of the newest edit still awaiting the server. An older edit that settles
  /// later must not overwrite it (#195 review).
  final Map<String, int> _pendingEdit = {};
  int _nextEditToken = 0;

  /// The latest list from the cache or the API, without this session's edits.
  Set<String> _base = const {};

  /// The account this list belongs to; null when signed out.
  String? _userId;

  /// Bumped by every [build]. In Riverpod 3 a rebuild keeps this Notifier instance and
  /// `ref.mounted` stays true, so async work started for the previous account compares the
  /// generation it captured instead, and drops its result if the account changed (#195 review).
  int _generation = 0;

  /// Completes once the first list for [_userId] is known: the cached list, or — with no cache —
  /// the first fetch's outcome, success or failure.
  Completer<void> _firstLoad = Completer<void>();

  /// True once a fetch has succeeded for [_userId]; until then resume/reconnect re-fetch.
  bool _fetched = false;
  bool _fetching = false;

  @override
  Set<String> build() {
    _generation++;
    // Edits belong to the account that made them.
    _edits.clear();
    _confirmed.clear();
    _pendingEdit.clear();
    _base = const {};
    _fetched = false;
    _fetching = false;
    _complete(_firstLoad); // release anyone waiting on the previous account's load
    _firstLoad = Completer<void>();
    // Rebuild (and reload) only when the signed-in account changes, not on every stat update.
    final userId = ref.watch(userProfileProvider.select((p) => p.userId));
    if (userId == null || userId.isEmpty) {
      _userId = null;
      _complete(_firstLoad);
      return const {};
    }
    _userId = userId;
    final generation = _generation;
    // A load that failed (5xx, or offline with no cache) is retried when the app resumes or the
    // hub reconnects — the triggers every other hydrated slice re-fetches on (#195 review).
    final retry = ref.watch(resyncTriggersProvider).listen((_) {
      if (_isCurrent(generation) && !_fetched && !_fetching) unawaited(_fetch(userId, generation));
    });
    ref.onDispose(retry.cancel);
    final firstLoad = _firstLoad;
    ref.onDispose(() => _complete(firstLoad));
    // Deliberately not awaited: build() must return synchronously; _load sets state when done.
    unawaited(_load(userId, generation, firstLoad));
    return const {};
  }

  static void _complete(Completer<void> load) {
    if (!load.isCompleted) load.complete();
  }

  /// Whether work started under [generation] still belongs to the signed-in account.
  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  /// [forUserId]'s block list once its first load has settled, or null if the signed-in account
  /// is no longer [forUserId]. For code that records a name for later (theft alerts go to the
  /// persisted inbox): reading [state] right after sign-in would see the empty initial set and
  /// record a blocked player's real name (#195 review). With a cached list the wait is one local
  /// file read.
  Future<Set<String>?> blockedIdsFor(String forUserId) async {
    final generation = _generation;
    await _firstLoad.future;
    return _isCurrent(generation) && _userId == forUserId ? state : null;
  }

  Set<String> _withEdits(Set<String> base) {
    final result = {...base};
    _edits.forEach((id, blocked) => blocked ? result.add(id) : result.remove(id));
    return result;
  }

  void _setBase(Set<String> base) {
    _base = base;
    state = _withEdits(base);
  }

  Future<void> _load(String userId, int generation, Completer<void> firstLoad) async {
    try {
      final cached = await BlockListCache.load(userId);
      if (!_isCurrent(generation)) return;
      if (cached != null) {
        _setBase(cached);
        _complete(firstLoad);
      }
      await _fetch(userId, generation);
    } finally {
      // The completer captured at the start — never a later account's.
      _complete(firstLoad);
    }
  }

  Future<void> _fetch(String userId, int generation) async {
    _fetching = true;
    try {
      final fresh = await ref.read(apiServiceProvider).getBlockedUserIds();
      if (!_isCurrent(generation)) return;
      _setBase(fresh);
      _fetched = true;
      await BlockListCache.save(userId, state);
    } catch (e, s) {
      // Offline: the cached list stays in force. Anything else is a real failure worth logging.
      if (!isServerUnreachable(e)) _log.warning('Failed to load block list', e, s);
    } finally {
      // A later account's fetch may be running: its flag is not ours to clear.
      if (_isCurrent(generation)) _fetching = false;
    }
  }

  /// Blocks [userId]. Masking applies immediately and is rolled back if the API refuses.
  /// Returns null on success, or a message to show.
  Future<String?> block(String userId) => _update(userId, blocking: true);

  /// Unblocks [userId]; same contract as [block].
  Future<String?> unblock(String userId) => _update(userId, blocking: false);

  Future<String?> _update(String userId, {required bool blocking}) async {
    final generation = _generation;
    final owner = _userId;
    final api = ref.read(apiServiceProvider);
    final token = ++_nextEditToken;
    _pendingEdit[userId] = token;
    _edits[userId] = blocking;
    state = _withEdits(_base);
    try {
      blocking ? await api.blockUser(userId) : await api.unblockUser(userId);
    } catch (e, s) {
      // Account changed while in flight: the edit maps now belong to the next account.
      if (_isCurrent(generation)) _settle(userId, token, accepted: null);
      if (isServerUnreachable(e)) return blockOfflineError;
      final serverReason = ApiService.clientErrorReason(e);
      if (serverReason == null) _log.warning('Block update failed unexpectedly', e, s);
      return serverReason ?? blockFailedError;
    }
    // Signed out (or switched account) while the request was in flight: nothing left to update.
    if (!_isCurrent(generation) || owner == null) return null;
    _settle(userId, token, accepted: blocking);
    await BlockListCache.save(owner, state);
    return null;
  }

  /// Records how edit [token] to [userId] ended: [accepted] is the value the server took, or null
  /// if it refused. Only the newest edit to an id changes what is shown — an older one settling
  /// while a newer one is in flight leaves it alone (#195 review). A refusal rolls back to the last
  /// accepted edit, not to "no edit", so an older server list can't undo an earlier success.
  void _settle(String userId, int token, {required bool? accepted}) {
    if (accepted != null) _confirmed[userId] = accepted;
    final newest = _pendingEdit[userId];
    if (newest != null && newest != token) return;
    _pendingEdit.remove(userId);
    final shown = _confirmed[userId];
    shown == null ? _edits.remove(userId) : _edits[userId] = shown;
    state = _withEdits(_base);
  }
}
