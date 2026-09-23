/// Regression test for PR #172 review round 1, finding 4.
///
/// Before #113, `userProfileProvider.notifier.clear()` on sign-out also zeroed
/// the stats, because they lived on `UserProfile`. Now `profileSliceProvider`
/// owns them, so sign-out must reset the slice too; otherwise the previous
/// player's hex count, streak, distance and rank stay in memory for whichever
/// route next skips seeding it.
///
/// #176 moved that reset into `UserSessionTeardown.clearUserBoundState`, which
/// every Sign Out and Delete Account entry point goes through, so this covers
/// all four: Profile screen and Home drawer, for both. A failed server delete
/// keeps the session — and with it the stats (App Store 5.1.1(v)).
library;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/features/profile/profile_screen.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';

const _seededHexCount = 140;
const _signOutLabel = 'Sign Out';
const _deleteAccountLabel = 'Delete Account';
const _confirmDeleteLabel = 'Delete';
const _maxIoRounds = 50;
const _ioRound = Duration(milliseconds: 20);

/// Implements (not extends) [AuthService] so the real class's eager
/// `FirebaseAuth.instance` initializer never runs without a Firebase app.
class _FakeAuthService implements AuthService {
  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteCurrentUser() async {}

  @override
  User? get currentUser => null;

  @override
  Stream<User?> get authStateChanges => const Stream.empty();

  @override
  Future<User?> signInWithGoogle() async => null;

  @override
  Future<User?> signInWithApple() async => null;
}

/// Server delete that succeeds, or fails like an offline / 5xx response.
class _FakeApi extends ApiService {
  _FakeApi({required this.deleteSucceeds});
  final bool deleteSucceeds;

  @override
  Future<void> deleteAccount(String userId) async {
    if (!deleteSucceeds) {
      throw DioException(requestOptions: RequestOptions(path: '/api/users/$userId'));
    }
  }
}

/// Stands in for the live-walk teardown, which does real file I/O that never
/// completes inside the widget tester's fake-async zone.
class _NoWalkJourneyController extends JourneyController {
  @override
  Future<void> abandonForSignOut(String? userId) async {}
}

/// Realtime service that never opens a SignalR connection.
class _FakeRealtime extends TerritoryRealtimeService {
  _FakeRealtime() : super(baseUrl: 'http://test.local');

  @override
  Future<void> disconnect() async {}
}

final _drawerHostKey = GlobalKey<ScaffoldState>();

/// One Sign Out / Delete Account entry point.
class _EndPath {
  const _EndPath({required this.drawer, required this.delete});
  final bool drawer;
  final bool delete;

  Widget host() => drawer
      ? Scaffold(key: _drawerHostKey, endDrawer: const ProfileDrawer(), body: const SizedBox())
      : const ProfileScreen();
}

const _paths = {
  'Profile screen Sign Out': _EndPath(drawer: false, delete: false),
  'Profile screen Delete Account': _EndPath(drawer: false, delete: true),
  'Home drawer Sign Out': _EndPath(drawer: true, delete: false),
  'Home drawer Delete Account': _EndPath(drawer: true, delete: true),
};

/// Pumps [path]'s host with a signed-in, stats-loaded profile, then runs the
/// sign-out or delete through the real UI and teardown. Returns the container.
Future<ProviderContainer> _endSession(
  WidgetTester tester,
  _EndPath path, {
  bool deleteSucceeds = true,
}) async {
  // The drawer's fixed-height column overflows the default 800x600 surface.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => path.host()),
    GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        territoryRealtimeProvider.overrideWithValue(_FakeRealtime()),
        authServiceProvider.overrideWithValue(_FakeAuthService()),
        apiServiceProvider.overrideWithValue(_FakeApi(deleteSucceeds: deleteSucceeds)),
        journeyControllerProvider.overrideWith(_NoWalkJourneyController.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  container.read(userProfileProvider.notifier).setFromApi(
        userId: 'user-1',
        avatarId: 0,
        color: '#000000',
        displayName: 'Player',
      );
  container.read(profileSliceProvider.notifier).applyStats(
        hexCount: _seededHexCount,
        streak: 4,
        distanceKm: 12.5,
        rank: 3,
      );
  await tester.pumpAndSettle();

  if (path.drawer) {
    _drawerHostKey.currentState!.openEndDrawer();
    await tester.pumpAndSettle();
  }
  final label = path.delete ? _deleteAccountLabel : _signOutLabel;
  // ProfileScreen is taller than the default test surface.
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  if (path.delete) {
    await tester.pumpAndSettle();
    await tester.tap(find.text(_confirmDeleteLabel));
  }
  await _finishTeardown(tester);
  return container;
}

/// The teardown clears file-backed caches; real file I/O only completes outside
/// the widget tester's fake-async zone, and until it does the modal progress
/// barrier's spinner keeps `pumpAndSettle` from settling.
Future<void> _finishTeardown(WidgetTester tester) async {
  final spinner = find.byType(CircularProgressIndicator);
  await tester.pump();
  for (var i = 0; i < _maxIoRounds && spinner.evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(_ioRound));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final MapEntry(key: name, value: path) in _paths.entries) {
    testWidgets('$name resets the displayed stats', (tester) async {
      final container = await _endSession(tester, path);

      final stats = container.read(profileSliceProvider);
      expect(stats.hexCount, 0);
      expect(stats.streak, 0);
      expect(stats.distanceKm, 0);
      expect(stats.rank, 0);
      expect(stats.isLoaded, isFalse);
    });
  }

  for (final MapEntry(key: name, value: path) in _paths.entries) {
    if (!path.delete) continue;
    testWidgets('$name that fails server-side keeps the session and its stats',
        (tester) async {
      final container = await _endSession(tester, path, deleteSucceeds: false);

      expect(container.read(profileSliceProvider).hexCount, _seededHexCount);
      expect(container.read(userProfileProvider).userId, 'user-1');
    });
  }
}
