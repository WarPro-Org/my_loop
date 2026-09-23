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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/game_state_cache.dart';
import 'package:myloop/shared/services/notification_cache.dart';
import 'package:myloop/shared/services/profile_cache.dart';
import 'package:myloop/shared/services/territory_cache.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';

final _log = Logger('UserSessionTeardown');

class UserSessionTeardown {
  UserSessionTeardown(this._ref);

  final Ref _ref;

  /// Clears all user-bound local state, then signs out of Firebase/Google.
  Future<void> signOut() async {
    await clearUserBoundState();
    await _ref.read(authServiceProvider).signOut();
  }

  /// Deletes the account server-side, clearing user-bound local state first so
  /// the deleted account's data (including undrained raw GPS points) does not
  /// outlive it on the device — App Store Guideline 5.1.1(v).
  ///
  /// No-op when no profile is loaded: there is no server account id to delete.
  Future<void> deleteAccount() async {
    final uid = _ref.read(userProfileProvider).userId;
    if (uid == null) return;
    final api = _ref.read(apiServiceProvider);
    final auth = _ref.read(authServiceProvider);
    await clearUserBoundState();
    try {
      await api.deleteAccount(uid);
      await auth.deleteCurrentUser();
    } catch (e) {
      // Firebase delete may fail if re-auth is needed — the account is already
      // gone server-side, so ending the session is the correct fallback.
      _log.warning('Account deletion did not complete cleanly; signing out', e);
      await auth.signOut();
    }
  }

  /// Tears down every piece of device-local state bound to the signed-in
  /// account. Each step is best-effort: a disk error clearing one cache must not
  /// abort the rest, nor stop the caller's Firebase sign-out from running.
  ///
  /// The live walk goes first: it stops GPS and the drain timer and clears the
  /// walk's own queue instance, so nothing can re-write this account's points
  /// once the profile (and with it the userId) is cleared below.
  Future<void> clearUserBoundState() async {
    final uid = _ref.read(userProfileProvider).userId;
    await _bestEffort(
      'live walk and step-claim queue',
      () => _ref.read(journeyControllerProvider.notifier).abandonForSignOut(uid),
    );
    _ref.read(userProfileProvider.notifier).clear();
    // In-memory game stats (#113/#172): without this the next account shows the
    // previous one's hex count, streak, distance and rank until it hydrates.
    _ref.invalidate(profileSliceProvider);
    // The hub connection is app-lifecycle-scoped (#102) — ending the session is
    // the one place it must actually be torn down.
    await _bestEffort(
      'realtime hub',
      () => _ref.read(territoryRealtimeProvider).disconnect(),
    );
    // Offline caches, so the next account can't inherit this session on a later
    // offline launch: profile (#19), home cards (#34), own-hex territories (#33),
    // notification inbox (#30).
    await _bestEffort('profile cache', ProfileCache.clear);
    await _bestEffort('game-state cache', GameStateCache.clear);
    await _bestEffort('territory cache', TerritoryCache.clear);
    await _bestEffort('notification cache', NotificationCache.clear);
  }

  Future<void> _bestEffort(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (e, st) {
      _log.warning('Failed to clear $what while ending the session', e, st);
    }
  }
}

final userSessionTeardownProvider =
    Provider<UserSessionTeardown>(UserSessionTeardown.new);
