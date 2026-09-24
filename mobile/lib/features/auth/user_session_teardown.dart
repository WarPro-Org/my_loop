/// Single owner of "end this account's session on this device".
///
/// Every sign-out and account-deletion entry point (Profile screen and the Home
/// drawer, for both) goes through [UserSessionTeardown] so a new piece of
/// user-bound local state only has to be cleared in one place. Before this
/// existed each path cleared its own hand-picked subset, and they drifted: the
/// drawer's Delete Account never cleared the step-claim WAL, and sign-out
/// cleared the WAL through a second queue instance while the live walk's queue
/// kept (and re-wrote) the outgoing account's GPS points (#110).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:logging/logging.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/block_list_cache.dart';
import 'package:myloop/shared/services/game_state_cache.dart';
import 'package:myloop/shared/services/notification_cache.dart';
import 'package:myloop/shared/services/notification_service.dart';
import 'package:myloop/shared/services/profile_cache.dart';
import 'package:myloop/shared/services/territory_cache.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/achievements_slice.dart';
import 'package:myloop/shared/state/exploration_slice.dart';
import 'package:myloop/shared/state/missions_slice.dart';
import 'package:myloop/shared/state/profile_slice.dart';
import 'package:myloop/shared/state/xp_slice.dart';

final _log = Logger('UserSessionTeardown');

class UserSessionTeardown {
  UserSessionTeardown(this._ref);

  final Ref _ref;

  /// Clears all user-bound local state, then signs out of Firebase/Google.
  Future<void> signOut() async {
    await clearUserBoundState();
    await _ref.read(authServiceProvider).signOut();
  }

  /// Deletes the account server-side and, only once that succeeded, ends the
  /// session. Returns whether the account was deleted.
  ///
  /// App Store Guideline 5.1.1(v): the user must never be told (or shown, by
  /// being signed out) that the account is gone while the server still holds
  /// it. So a failed server delete returns false with the session intact —
  /// profile, caches, hub and Firebase sign-in untouched — and the caller tells
  /// the user to try again. Only a Firebase-side failure AFTER the server delete
  /// falls back to signing out, because by then the account really is gone.
  ///
  /// The live walk is torn down first either way: that stops GPS and the drain,
  /// so no batch can race the server delete, and the account's undrained raw
  /// GPS points are wiped even if the delete then fails.
  Future<bool> deleteAccount() async {
    final uid = _ref.read(userProfileProvider).userId;
    if (uid == null) return false;
    await _endLiveWalk(uid);
    try {
      await _ref.read(apiServiceProvider).deleteAccount(uid);
    } catch (e, st) {
      _log.warning('Server account deletion failed; keeping the session', e, st);
      return false;
    }
    await clearUserBoundState();
    final auth = _ref.read(authServiceProvider);
    try {
      await auth.deleteCurrentUser();
    } catch (e, st) {
      // Typically Firebase wanting a recent re-authentication. The server
      // account is already deleted, so ending the session is correct.
      _log.warning('Firebase user deletion failed after the server delete; signing out', e, st);
      await auth.signOut();
    }
    return true;
  }

  /// Tears down every piece of device-local state bound to the signed-in
  /// account. Each step is best-effort: a disk error clearing one cache must not
  /// abort the rest, nor stop the caller's Firebase sign-out from running.
  /// Idempotent, so a forced sign-out racing a tapped one is harmless.
  ///
  /// The live walk goes first: it stops GPS and the drain timer and clears the
  /// walk's own queue instance, so nothing can re-write this account's points
  /// once the profile (and with it the userId) is cleared below.
  Future<void> clearUserBoundState() async {
    final uid = _ref.read(userProfileProvider).userId;
    await _endLiveWalk(uid);
    _ref.read(userProfileProvider.notifier).clear();
    // The hub connection is app-lifecycle-scoped (#102) — ending the session is
    // the one place it must actually be torn down. It goes before the in-memory
    // reset below so a late XP/mission/achievement push for this account can't
    // land in the freshly reset slices.
    await _bestEffort(
      'realtime hub',
      () => _ref.read(territoryRealtimeProvider).disconnect(),
    );
    await _resetInMemoryState();
    // Offline caches, so the next account can't inherit this session on a later
    // offline launch: profile (#19), home cards (#34), own-hex territories (#33),
    // notification inbox (#30), block list (#190).
    await _bestEffort('profile cache', ProfileCache.clear);
    await _bestEffort('game-state cache', GameStateCache.clear);
    await _bestEffort('territory cache', TerritoryCache.clear);
    await _bestEffort('notification cache', NotificationCache.clear);
    await _bestEffort('block list cache', BlockListCache.clear);
  }

  /// Resets every app-lifetime provider that holds this account's data in
  /// memory. They are only overwritten when the next account's game-state
  /// fetch succeeds, so without this a failed fetch leaves the next account
  /// looking at this one's stats, level, missions, achievements, explored
  /// neighbourhoods (location-derived) and theft alerts.
  ///
  /// Runs after the profile is cleared: hydration re-checks the signed-in user
  /// after every await, so no in-flight resync can re-fill a slice past here.
  Future<void> _resetInMemoryState() async {
    for (final slice in _userBoundSlices) {
      _ref.invalidate(slice);
    }
    // The inbox's queued disk write reads the notifier's `ref`, which throws
    // once the notifier is disposed, so let it finish first. With the profile
    // already cleared it writes nothing.
    if (_ref.exists(notificationProvider)) {
      await _bestEffort(
        'pending notification write',
        () => _ref.read(notificationProvider.notifier).pendingWrite,
      );
    }
    _ref.invalidate(notificationProvider);
  }

  Future<void> _endLiveWalk(String? uid) => _bestEffort(
        'live walk and step-claim queue',
        () => _ref.read(journeyControllerProvider.notifier).abandonForSignOut(uid),
      );

  Future<void> _bestEffort(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (e, st) {
      _log.warning('Failed to clear $what while ending the session', e, st);
    }
  }
}

/// The game-state slices filled by `hydrateAllSlices`. A slice added there
/// holds account data too, so it belongs here as well.
final List<ProviderOrFamily> _userBoundSlices = [
  profileSliceProvider,
  xpSliceProvider,
  missionsSliceProvider,
  achievementsSliceProvider,
  explorationSliceProvider,
];

final userSessionTeardownProvider =
    Provider<UserSessionTeardown>(UserSessionTeardown.new);

/// Runs [UserSessionTeardown.clearUserBoundState] when Firebase ends the
/// session without going through the app's UI — the account deleted on another
/// device, a revoked refresh token, a disabled user (#110).
///
/// The router's auth listener only redirects to `/login`. Without this, the
/// global (non-autoDispose) journey controller would keep the walk, its queue
/// and its drain alive, and the next account's token would carry them. A
/// UI-driven sign-out has already cleared the profile by the time Firebase
/// emits null, so for it this is a no-op.
final forcedSignOutGuardProvider = Provider<void>((ref) {
  final sub = ref.read(authServiceProvider).authStateChanges.listen((user) {
    if (user != null) return;
    if (ref.read(userProfileProvider).userId == null) return;
    _log.info('Session ended outside the app; clearing user-bound state');
    unawaited(ref.read(userSessionTeardownProvider).clearUserBoundState());
  });
  ref.onDispose(sub.cancel);
});
