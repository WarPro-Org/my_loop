/// The UI half of ending a session (#110): every Sign Out and Delete Account
/// entry point (Profile screen and Home drawer) runs [UserSessionTeardown]
/// behind a non-dismissible modal progress barrier, then routes on.
///
/// The barrier matters for correctness, not just polish: while the teardown
/// runs, the outgoing account's profile is still loaded, so an interactive
/// screen would let the user start a walk (or tap Sign Out again) mid-teardown.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:myloop/app/router_guards.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/shared/constants/app_constants.dart';

final _log = Logger('SessionEndUi');

class SessionEndUi {
  /// Captures the navigator, router and messenger from [context] up front, so
  /// the flow keeps working after the widget that started it (a drawer, a
  /// dialog) has been popped and unmounted.
  SessionEndUi.of(BuildContext context)
      : _navigator = Navigator.of(context, rootNavigator: true),
        _router = GoRouter.of(context),
        _messenger = ScaffoldMessenger.of(context);

  final NavigatorState _navigator;
  final GoRouter _router;
  final ScaffoldMessengerState _messenger;

  /// Signs out, then routes to login.
  ///
  /// If the Google/Firebase sign-out throws, this account's local state is
  /// already torn down, so the user is still sent to login rather than left on
  /// a screen whose profile is gone. They are told to try again: Firebase may
  /// still hold the session, in which case login resumes it as the same
  /// account — never another one.
  Future<void> signOut(UserSessionTeardown teardown) async {
    try {
      await _behindBarrier(AppConstants.signingOutLabel, teardown.signOut);
    } catch (e, st) {
      _log.warning('Sign-out failed after the local teardown; routing to login', e, st);
      _router.go(loginRoute);
      _messenger.showSnackBar(
        const SnackBar(content: Text(AppConstants.signOutFailedMessage)),
      );
      return;
    }
    _router.go(loginRoute);
  }

  /// Deletes the account, then routes to login. When the server delete fails
  /// the user stays signed in where they are and is told to try again — never
  /// sent to login as if the account were gone (App Store 5.1.1(v)).
  Future<void> deleteAccount(UserSessionTeardown teardown) async {
    final deleted =
        await _behindBarrier(AppConstants.deletingAccountLabel, teardown.deleteAccount);
    if (deleted) {
      _router.go(loginRoute);
      return;
    }
    _messenger.showSnackBar(
      const SnackBar(content: Text(AppConstants.deleteAccountFailedMessage)),
    );
  }

  Future<T> _behindBarrier<T>(String label, Future<T> Function() task) async {
    final barrier = DialogRoute<void>(
      context: _navigator.context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator(semanticsLabel: label)),
      ),
    );
    unawaited(_navigator.push(barrier));
    try {
      return await task();
    } finally {
      // Firebase's sign-out can already have sent the router to login, which
      // removes the barrier along with the page it sat on.
      if (barrier.isActive) _navigator.removeRoute(barrier);
    }
  }
}
