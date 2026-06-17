/// Regression test for issue #30 — "Hex count is different while tracking vs in-app".
///
/// Root cause: the server pushes an authoritative [UserStatsDelta] over SignalR on
/// every claim (including each batch-step claim while walking), but only
/// `profileSliceProvider` consumed it. Every user-facing surface (Map badge, Home,
/// Profile) reads `userProfileProvider`, which was NOT subscribed to those pushes —
/// so the displayed hex count stayed frozen at its pre-walk value mid-walk and only
/// reconciled after the post-walk refresh, diverging from the real server count.
///
/// The fix subscribes `userProfileProvider` to `onUserStats`. This test drives a
/// fake realtime service and asserts the displayed profile tracks the pushed stats.
/// It FAILS without the fix (hexCount stays at the pre-walk value).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';

/// Fake realtime service whose [onUserStats] stream is driven by the test.
/// Only the stat-push stream is overridden; no SignalR connection is made.
class _FakeRealtime extends TerritoryRealtimeService {
  _FakeRealtime() : super(baseUrl: 'http://test.local');

  final StreamController<UserStatsDelta> _stats =
      StreamController<UserStatsDelta>.broadcast();

  void push(UserStatsDelta delta) => _stats.add(delta);

  @override
  Stream<UserStatsDelta> get onUserStats => _stats.stream;

  Future<void> close() => _stats.close();
}

UserStatsDelta _delta({
  required int hexCount,
  int streak = 0,
  double distanceKm = 0,
}) =>
    UserStatsDelta.fromJson({
      'hexCount': hexCount,
      'totalHexesCaptured': hexCount,
      'totalHexesStolen': 0,
      'streak': streak,
      'isStreakActive': streak > 0,
      'distanceKm': distanceKm,
    });

void main() {
  late _FakeRealtime realtime;
  late ProviderContainer container;

  setUp(() {
    realtime = _FakeRealtime();
    container = ProviderContainer(overrides: [
      territoryRealtimeProvider.overrideWithValue(realtime),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await realtime.close();
  });

  // Lets the broadcast stream deliver its queued event to the listener.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a live stat push updates the displayed hex count mid-walk', () async {
    final notifier = container.read(userProfileProvider.notifier);
    // Establish the pre-walk baseline the Map/Home badge shows.
    notifier.setFromApi(
      userId: 'user-1',
      avatarId: 2,
      color: '#00D4AA',
      displayName: 'Robin',
      hexCount: 100,
      streak: 4,
      distanceKm: 5.0,
      rank: 7,
    );
    expect(container.read(userProfileProvider).hexCount, 100);

    // Server pushes the authoritative count after capturing 30 hexes this walk.
    realtime.push(_delta(hexCount: 130, streak: 5, distanceKm: 6.2));
    await settle();

    final profile = container.read(userProfileProvider);
    expect(profile.hexCount, 130, reason: 'Map badge must track the live server count');
    expect(profile.streak, 5);
    expect(profile.distanceKm, 6.2);
  });

  test('stat pushes preserve identity and rank (only stat fields change)', () async {
    final notifier = container.read(userProfileProvider.notifier);
    notifier.setFromApi(
      userId: 'user-1',
      avatarId: 2,
      color: '#6C5CE7',
      displayName: 'Robin',
      hexCount: 100,
      streak: 4,
      distanceKm: 5.0,
      rank: 7,
    );

    realtime.push(_delta(hexCount: 142, streak: 5, distanceKm: 6.2));
    await settle();

    final profile = container.read(userProfileProvider);
    // Stat fields updated…
    expect(profile.hexCount, 142);
    // …identity and rank (not carried by the delta) are preserved.
    expect(profile.userId, 'user-1');
    expect(profile.avatarId, 2);
    expect(profile.color, '#6C5CE7');
    expect(profile.displayName, 'Robin');
    expect(profile.rank, 7);
  });

  test('successive pushes during a walk keep replacing the displayed count', () async {
    container.read(userProfileProvider.notifier).setFromApi(
          userId: 'user-1',
          avatarId: 0,
          color: '#00D4AA',
          displayName: 'Robin',
          hexCount: 50,
          streak: 1,
          distanceKm: 0,
        );

    realtime.push(_delta(hexCount: 55));
    await settle();
    expect(container.read(userProfileProvider).hexCount, 55);

    realtime.push(_delta(hexCount: 61));
    await settle();
    expect(container.read(userProfileProvider).hexCount, 61);
  });
}
