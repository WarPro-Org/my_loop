/// Every sign-out and account-deletion entry point must go through the one
/// shared [UserSessionTeardown] (#110 review finding 2). Before it existed each
/// path cleared its own subset of user-bound state and they drifted — the Home
/// drawer's Delete Account never cleared the step-claim WAL. What the teardown
/// itself clears is covered in `user_session_teardown_test.dart`; this file
/// pins that all four UI paths reach it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/features/profile/profile_screen.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

const _signOutLabel = 'Sign Out';
const _deleteAccountLabel = 'Delete Account';
const _confirmDeleteLabel = 'Delete';
const _loginMarker = 'login-page';

class _RecordingTeardown extends UserSessionTeardown {
  _RecordingTeardown(super.ref);
  int signOutCalls = 0;
  int deleteCalls = 0;

  /// What [deleteAccount] reports: false = the server delete failed.
  bool deleteSucceeds = true;

  /// When set, the teardown runs until it completes — lets a test look at the
  /// UI mid-teardown.
  Completer<void>? hold;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await hold?.future;
  }

  @override
  Future<bool> deleteAccount() async {
    deleteCalls++;
    await hold?.future;
    return deleteSucceeds;
  }
}

class _FakeRealtime extends TerritoryRealtimeService {
  _FakeRealtime() : super(baseUrl: 'http://test.local');

  @override
  Future<void> disconnect() async {}
}

final _drawerHostKey = GlobalKey<ScaffoldState>();

/// Pumps [home] at `/` and returns the recorder the teardown provider yields.
/// [hold] and [deleteSucceeds] configure that recorder.
Future<_RecordingTeardown Function()> _pump(
  WidgetTester tester,
  Widget home, {
  Completer<void>? hold,
  bool deleteSucceeds = true,
}) async {
  // The drawer's fixed-height column overflows the default 800x600 surface.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _RecordingTeardown? recorder;
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(path: '/login', builder: (_, _) => const Text(_loginMarker)),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      territoryRealtimeProvider.overrideWithValue(_FakeRealtime()),
      userSessionTeardownProvider.overrideWith((ref) => recorder = _RecordingTeardown(ref)
        ..hold = hold
        ..deleteSucceeds = deleteSucceeds),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return () => recorder!;
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _openDrawer(WidgetTester tester) async {
  _drawerHostKey.currentState!.openEndDrawer();
  await tester.pumpAndSettle();
}

Widget get _drawerHost =>
    Scaffold(key: _drawerHostKey, endDrawer: const ProfileDrawer(), body: const SizedBox());

void main() {
  testWidgets('Profile screen Sign Out goes through the shared teardown', (tester) async {
    final recorder = await _pump(tester, const ProfileScreen());
    await _tapVisible(tester, _signOutLabel);
    expect(recorder().signOutCalls, 1);
    expect(recorder().deleteCalls, 0);
  });

  testWidgets('Profile screen Delete Account goes through the shared teardown', (tester) async {
    final recorder = await _pump(tester, const ProfileScreen());
    await _tapVisible(tester, _deleteAccountLabel);
    await _tapVisible(tester, _confirmDeleteLabel);
    expect(recorder().deleteCalls, 1);
    expect(recorder().signOutCalls, 0);
  });

  testWidgets('Home drawer Sign Out goes through the shared teardown', (tester) async {
    final recorder = await _pump(tester, _drawerHost);
    await _openDrawer(tester);
    await _tapVisible(tester, _signOutLabel);
    expect(recorder().signOutCalls, 1);
    expect(recorder().deleteCalls, 0);
  });

  testWidgets('Home drawer Delete Account goes through the shared teardown', (tester) async {
    final recorder = await _pump(tester, _drawerHost);
    await _openDrawer(tester);
    await _tapVisible(tester, _deleteAccountLabel);
    await _tapVisible(tester, _confirmDeleteLabel);
    expect(recorder().deleteCalls, 1);
    expect(recorder().signOutCalls, 0);
  });

  // ── #110 round 2: modal barrier while the teardown runs; honest delete ──

  final paths = <String, _EndPath>{
    'Profile screen Sign Out': _EndPath(() => const ProfileScreen(), drawer: false, delete: false),
    'Profile screen Delete Account': _EndPath(() => const ProfileScreen(), drawer: false, delete: true),
    'Home drawer Sign Out': _EndPath(() => _drawerHost, drawer: true, delete: false),
    'Home drawer Delete Account': _EndPath(() => _drawerHost, drawer: true, delete: true),
  };

  for (final MapEntry(key: name, value: path) in paths.entries) {
    testWidgets('$name blocks the UI behind a modal barrier until the teardown ends',
        (tester) async {
      final hold = Completer<void>();
      await _pump(tester, path.host(), hold: hold);
      await path.start(tester);

      final barrier = _barrier(path.delete ? AppConstants.deletingAccountLabel : AppConstants.signingOutLabel);
      expect(barrier, findsOneWidget);
      // Neither a tap outside nor system back dismisses it.
      await tester.tapAt(const Offset(4, 4));
      await _pumpTransition(tester);
      expect(barrier, findsOneWidget, reason: 'a barrier tap must not dismiss it');
      await tester.binding.handlePopRoute();
      await _pumpTransition(tester);
      expect(barrier, findsOneWidget, reason: 'system back must not dismiss it');
      expect(find.text(_loginMarker), findsNothing);

      hold.complete();
      await tester.pumpAndSettle();
      expect(barrier, findsNothing);
      expect(find.text(_loginMarker), findsOneWidget);
    });
  }

  for (final MapEntry(key: name, value: path) in paths.entries) {
    if (!path.delete) continue;
    testWidgets('$name that fails server-side stays signed in and says so', (tester) async {
      await _pump(tester, path.host(), deleteSucceeds: false);
      await path.start(tester);
      await tester.pumpAndSettle();

      expect(find.text(AppConstants.deleteAccountFailedMessage), findsOneWidget);
      expect(find.text(_loginMarker), findsNothing,
          reason: 'must not look like the account was deleted');
      expect(_barrier(AppConstants.deletingAccountLabel), findsNothing);
    });
  }
}

/// Long enough for a dialog/drawer route transition to finish.
const _routeTransition = Duration(milliseconds: 500);

Finder _barrier(String label) => find.byWidgetPredicate(
    (w) => w is CircularProgressIndicator && w.semanticsLabel == label);

/// One Sign Out / Delete Account entry point.
class _EndPath {
  _EndPath(this.host, {required this.drawer, required this.delete});
  final Widget Function() host;
  final bool drawer;
  final bool delete;

  /// Taps through to the point where the teardown starts, without settling
  /// (the barrier's spinner never settles).
  Future<void> start(WidgetTester tester) async {
    if (drawer) await _openDrawer(tester);
    final label = delete ? _deleteAccountLabel : _signOutLabel;
    if (delete) {
      await _tapVisible(tester, label);
      await tester.tap(find.text(_confirmDeleteLabel));
    } else {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }
    await _pumpTransition(tester);
  }
}

/// Runs a route transition to completion frame by frame: one long `pump` runs a
/// single frame, which ends the animation but not the route's removal.
Future<void> _pumpTransition(WidgetTester tester) async {
  for (var t = Duration.zero; t < _routeTransition; t += _frame) {
    await tester.pump(_frame);
  }
}

const _frame = Duration(milliseconds: 50);
