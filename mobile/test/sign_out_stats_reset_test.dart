/// Regression test for PR #172 review round 1, finding 4.
///
/// Before #113, `userProfileProvider.notifier.clear()` on sign-out also zeroed
/// the stats, because they lived on `UserProfile`. Now `profileSliceProvider`
/// owns them, so sign-out must reset the slice too; otherwise the previous
/// player's hex count, streak, distance and rank stay in memory for whichever
/// route next skips seeding it.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/profile/profile_screen.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';

/// Implements (not extends) [AuthService] so the real class's eager
/// `FirebaseAuth.instance` initializer never runs without a Firebase app.
class _FakeAuthService implements AuthService {
  @override
  Future<void> signOut() async {}

  @override
  User? get currentUser => null;

  @override
  Stream<User?> get authStateChanges => const Stream.empty();

  @override
  Future<User?> signInWithGoogle() async => null;

  @override
  Future<User?> signInWithApple() async => null;
}

/// Realtime service that never opens a SignalR connection.
class _FakeRealtime extends TerritoryRealtimeService {
  _FakeRealtime() : super(baseUrl: 'http://test.local');

  @override
  Future<void> disconnect() async {}
}

void main() {
  testWidgets('signing out from the Profile screen resets the displayed stats',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          territoryRealtimeProvider.overrideWithValue(_FakeRealtime()),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    container.read(userProfileProvider.notifier).setFromApi(
          userId: 'user-1',
          avatarId: 0,
          color: '#000000',
          displayName: 'Player',
        );
    container.read(profileSliceProvider.notifier).applyStats(
          hexCount: 140,
          streak: 4,
          distanceKm: 12.5,
          rank: 3,
        );
    await tester.pumpAndSettle();

    // ProfileScreen is taller than the default test surface.
    await tester.ensureVisible(find.text('Sign Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    final stats = container.read(profileSliceProvider);
    expect(stats.hexCount, 0);
    expect(stats.streak, 0);
    expect(stats.distanceKm, 0);
    expect(stats.rank, 0);
    expect(stats.isLoaded, isFalse);
  });
}
