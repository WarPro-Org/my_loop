/// Every sign-out and account-deletion entry point must go through the one
/// shared [UserSessionTeardown] (#110 review finding 2). Before it existed each
/// path cleared its own subset of user-bound state and they drifted — the Home
/// drawer's Delete Account never cleared the step-claim WAL. What the teardown
/// itself clears is covered in `user_session_teardown_test.dart`; this file
/// pins that all four UI paths reach it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/features/profile/profile_screen.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

const _signOutLabel = 'Sign Out';
const _deleteAccountLabel = 'Delete Account';
const _confirmDeleteLabel = 'Delete';

class _RecordingTeardown extends UserSessionTeardown {
  _RecordingTeardown(super.ref);
  int signOutCalls = 0;
  int deleteCalls = 0;

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  Future<void> deleteAccount() async => deleteCalls++;
}

class _FakeRealtime extends TerritoryRealtimeService {
  _FakeRealtime() : super(baseUrl: 'http://test.local');

  @override
  Future<void> disconnect() async {}
}

final _drawerHostKey = GlobalKey<ScaffoldState>();

/// Pumps [home] at `/` and returns the recorder the teardown provider yields.
Future<_RecordingTeardown Function()> _pump(WidgetTester tester, Widget home) async {
  // The drawer's fixed-height column overflows the default 800x600 surface.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _RecordingTeardown? recorder;
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      territoryRealtimeProvider.overrideWithValue(_FakeRealtime()),
      userSessionTeardownProvider.overrideWith((ref) => recorder = _RecordingTeardown(ref)),
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
}
