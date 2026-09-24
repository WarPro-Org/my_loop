/// Regression tests for PR #172 review round 1, finding 4, and PR #176 review
/// round 3, findings 1 and 2.
///
/// Before #113, `userProfileProvider.notifier.clear()` on sign-out also zeroed
/// the stats, because they lived on `UserProfile`. Now `profileSliceProvider`
/// owns them, so sign-out must reset the slice too; otherwise the previous
/// player's hex count, streak, distance and rank stay in memory for whichever
/// route next skips seeding it.
///
/// The same holds for every other app-lifetime, user-bound provider: the XP,
/// missions, achievements and exploration slices, and the notification inbox.
/// They are only overwritten when the next account's game-state fetch
/// succeeds, so a failed fetch (which `getGameState` collapses to null) used to
/// show account B account A's level, missions, explored neighbourhoods and
/// theft alerts (#176 round 3, finding 1).
///
/// #176 moved the reset into `UserSessionTeardown.clearUserBoundState`, which
/// every Sign Out and Delete Account entry point goes through, so this covers
/// all four: Profile screen and Home drawer, for both, plus the forced
/// sign-out guard. A failed server delete keeps the session — and with it the
/// state (App Store 5.1.1(v)).
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/features/profile/profile_screen.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/notification_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/achievements_slice.dart';
import 'package:myloop/shared/state/exploration_slice.dart';
import 'package:myloop/shared/state/hydration.dart';
import 'package:myloop/shared/state/missions_slice.dart';
import 'package:myloop/shared/state/profile_slice.dart';
import 'package:myloop/shared/state/xp_slice.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _userA = 'user-a';
const _userB = 'user-b';
const _seededHexCount = 140;
const _seededLevel = 42;
const _defaultLevel = 1;
const _signOutLabel = 'Sign Out';
const _deleteAccountLabel = 'Delete Account';
const _confirmDeleteLabel = 'Delete';
const _loginMarker = 'login-screen';
const _maxIoRounds = 50;
const _ioRound = Duration(milliseconds: 20);

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Implements (not extends) [AuthService] so the real class's eager
/// `FirebaseAuth.instance` initializer never runs without a Firebase app.
class _FakeAuthService implements AuthService {
  _FakeAuthService({this.signOutThrows = false});
  final bool signOutThrows;
  final authStates = StreamController<User?>.broadcast();

  @override
  Future<void> signOut() async {
    if (signOutThrows) throw StateError('Google sign-out failed');
  }

  @override
  Future<void> deleteCurrentUser() async {}

  @override
  User? get currentUser => null;

  @override
  Stream<User?> get authStateChanges => authStates.stream;

  @override
  Future<User?> signInWithGoogle() async => null;

  @override
  Future<User?> signInWithApple() async => null;
}

/// Server delete that succeeds, or fails like an offline / 5xx response.
/// Game-state always fails, the way `getGameState` reports any failure.
class _FakeApi extends ApiService {
  _FakeApi({this.deleteSucceeds = true});
  final bool deleteSucceeds;

  @override
  Future<void> deleteAccount(String userId) async {
    if (!deleteSucceeds) {
      throw DioException(requestOptions: RequestOptions(path: '/api/users/$userId'));
    }
  }

  @override
  Future<Map<String, dynamic>?> getGameState(String userId) async => null;
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

List<Override> _overrides({required _FakeAuthService auth, required _FakeApi api}) => [
      territoryRealtimeProvider.overrideWithValue(_FakeRealtime()),
      authServiceProvider.overrideWithValue(auth),
      apiServiceProvider.overrideWithValue(api),
      journeyControllerProvider.overrideWith(_NoWalkJourneyController.new),
    ];

/// Gives plain tests a [Ref] for [hydrateAllSlicesFromRef].
final _hydrateFromRefProvider =
    Provider<Future<bool> Function()>((ref) => () => hydrateAllSlicesFromRef(ref));

void _signIn(ProviderContainer c, String userId) =>
    c.read(userProfileProvider.notifier).setFromApi(
          userId: userId,
          avatarId: 0,
          color: '#000000',
          displayName: 'Player $userId',
        );

/// Signs in as account A and fills every user-bound provider the way a
/// successful hydration plus a theft alert would.
void _seedAccountA(ProviderContainer c) {
  _signIn(c, _userA);
  c.read(profileSliceProvider.notifier).applyStats(
        hexCount: _seededHexCount,
        streak: 4,
        distanceKm: 12.5,
        rank: 3,
      );
  c.read(xpSliceProvider.notifier).hydrate({
    'xp': {
      'totalXp': 90000,
      'level': _seededLevel,
      'progressXp': 50,
      'neededXp': 400,
      'progressPercent': 12.5,
    },
  });
  c.read(missionsSliceProvider.notifier).hydrate([
    {'id': 'mission-a', 'description': 'Walk 2 km', 'targetValue': 2, 'currentProgress': 1},
  ]);
  c.read(achievementsSliceProvider.notifier).hydrate([
    {'id': 'first-loop', 'name': 'First Loop', 'unlocked': true},
  ]);
  c.read(explorationSliceProvider.notifier).hydrate([
    {
      'neighborhoodId': 7,
      'centerLat': 51.52,
      'centerLng': -0.08,
      'exploredCount': 3,
      'totalCount': 10,
      'percent': 30.0,
      'areaName': 'Shoreditch',
    },
  ]);
  c.read(notificationProvider.notifier).addTheftAlert(
        thiefName: 'Rival',
        thiefColor: '#FF0000',
        hexCount: 2,
      );
}

void _expectAccountAState(ProviderContainer c) {
  expect(c.read(userProfileProvider).userId, _userA);
  expect(c.read(profileSliceProvider).hexCount, _seededHexCount);
  expect(c.read(xpSliceProvider).level, _seededLevel);
  expect(c.read(missionsSliceProvider).missions, isNotEmpty);
  expect(c.read(achievementsSliceProvider).achievements, isNotEmpty);
  expect(c.read(explorationSliceProvider).neighborhoods, isNotEmpty);
  expect(c.read(notificationProvider), isNotEmpty);
}

void _expectAllReset(ProviderContainer c) {
  final stats = c.read(profileSliceProvider);
  expect(stats.hexCount, 0);
  expect(stats.streak, 0);
  expect(stats.distanceKm, 0);
  expect(stats.rank, 0);
  expect(stats.isLoaded, isFalse);

  final xp = c.read(xpSliceProvider);
  expect(xp.level, _defaultLevel, reason: "the previous account's level");
  expect(xp.totalXp, 0);
  expect(xp.isLoaded, isFalse);

  final missions = c.read(missionsSliceProvider);
  expect(missions.missions, isEmpty, reason: "the previous account's missions");
  expect(missions.isLoaded, isFalse);

  final achievements = c.read(achievementsSliceProvider);
  expect(achievements.achievements, isEmpty);
  expect(achievements.isLoaded, isFalse);

  final exploration = c.read(explorationSliceProvider);
  expect(exploration.neighborhoods, isEmpty,
      reason: "the previous account's explored neighbourhoods (location data)");
  expect(exploration.isLoaded, isFalse);

  expect(c.read(notificationProvider), isEmpty,
      reason: "the previous account's theft alerts");
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

/// Pumps [path]'s host with account A signed in and every user-bound provider
/// filled, then runs the sign-out or delete through the real UI and teardown.
/// Returns the container.
Future<ProviderContainer> _endSession(
  WidgetTester tester,
  _EndPath path, {
  bool deleteSucceeds = true,
  bool signOutThrows = false,
}) async {
  // The drawer's fixed-height column overflows the default 800x600 surface.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => path.host()),
    GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text(_loginMarker))),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        auth: _FakeAuthService(signOutThrows: signOutThrows),
        api: _FakeApi(deleteSucceeds: deleteSucceeds),
      ),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  _seedAccountA(container);
  await _finishIo(tester);
  _expectAccountAState(container);

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
  await _finishIo(tester);
  return container;
}

/// The teardown and the notification inbox do file I/O; real file I/O only
/// completes outside the widget tester's fake-async zone, and until it does the
/// modal progress barrier's spinner keeps `pumpAndSettle` from settling.
Future<void> _finishIo(WidgetTester tester) async {
  final spinner = find.byType(CircularProgressIndicator);
  await tester.pump();
  for (var i = 0; i < _maxIoRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(_ioRound));
    await tester.pump();
    if (spinner.evaluate().isEmpty && i > 0) break;
  }
  await tester.pumpAndSettle();
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < _maxIoRounds && !condition(); i++) {
    await Future<void>.delayed(_ioRound);
  }
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sign_out_stats_reset_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  for (final MapEntry(key: name, value: path) in _paths.entries) {
    testWidgets('$name resets every user-bound slice and the inbox', (tester) async {
      final container = await _endSession(tester, path);

      expect(container.read(userProfileProvider).userId, isNull);
      _expectAllReset(container);
    });
  }

  for (final MapEntry(key: name, value: path) in _paths.entries) {
    if (!path.delete) continue;
    testWidgets('$name that fails server-side keeps the session and its state',
        (tester) async {
      final container = await _endSession(tester, path, deleteSucceeds: false);

      _expectAccountAState(container);
    });
  }

  for (final MapEntry(key: name, value: path) in _paths.entries) {
    if (path.delete) continue;
    testWidgets('$name that throws in Firebase still routes to login and says so',
        (tester) async {
      final container = await _endSession(tester, path, signOutThrows: true);

      expect(tester.takeException(), isNull);
      expect(find.text(_loginMarker), findsOneWidget);
      expect(find.text(AppConstants.signOutFailedMessage), findsOneWidget);
      _expectAllReset(container);
    });
  }

  group('without the UI', () {
    late _FakeAuthService auth;
    late ProviderContainer container;

    setUp(() {
      auth = _FakeAuthService();
      container = ProviderContainer(overrides: _overrides(auth: auth, api: _FakeApi()));
    });

    tearDown(() async {
      container.dispose();
      await auth.authStates.close();
    });

    test('the forced sign-out guard resets every user-bound slice and the inbox',
        () async {
      container.read(forcedSignOutGuardProvider);
      _seedAccountA(container);
      _expectAccountAState(container);

      // E.g. the account was deleted on another device: Firebase emits null
      // without the app's UI being involved.
      auth.authStates.add(null);
      await _until(() => container.read(xpSliceProvider).level != _seededLevel);

      expect(container.read(userProfileProvider).userId, isNull);
      _expectAllReset(container);
    });

    test("account B whose game-state fails never sees account A's state", () async {
      _seedAccountA(container);
      await container.read(userSessionTeardownProvider).clearUserBoundState();

      _signIn(container, _userB);
      final applied = await container.read(_hydrateFromRefProvider)();

      expect(applied, isFalse, reason: 'the fake game-state fetch fails');
      _expectAllReset(container);
    });

    test('a game-state response without an xp object resets XP to the defaults',
        () {
      _seedAccountA(container);

      container.read(xpSliceProvider.notifier).hydrate(const <String, dynamic>{});

      final xp = container.read(xpSliceProvider);
      expect(xp.level, _defaultLevel);
      expect(xp.totalXp, 0);
      expect(xp.isLoaded, isFalse);
    });
  });
}
