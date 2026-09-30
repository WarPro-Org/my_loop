/// Bug B1 (PRIV-1, PRIV-2, LEG-1): 0.1 is single-player, so the app shows no leaderboard, no
/// other player's profile and no in-app theft alert, while the player's own live updates still
/// arrive through their personal group.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

/// A shell like the app's: `/home` and `/achievements` share one bottom bar.
GoRouter _shell() => GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in ['/home', '/achievements'])
          GoRoute(
            path: path,
            builder: (context, state) => Scaffold(
              body: Text('at $path'),
              bottomNavigationBar: HomeBottomNav(currentIndex: homeTabIndexFor(path)),
            ),
          ),
      ],
    );

/// Every Dart file under `lib/`, as (path, source).
Iterable<(String, String)> _libSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => (f.path, f.readAsStringSync()));

void main() {
  group('bottom bar', () {
    testWidgets('has no leaderboard tab', (tester) async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: _shell())));

      final bar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bar.items.map((i) => i.label), ['Home', 'Achievements', '']);
      expect(find.byIcon(Icons.leaderboard_outlined), findsNothing);
    });

    testWidgets('the Achievements tab opens achievements and is shown as selected', (tester) async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: _shell())));

      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('at /achievements'), findsOneWidget);
      final bar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bar.items[bar.currentIndex].label, 'Achievements');
    });
  });

  test('no screen or route shows other players, and no text says they can see you', () {
    const banned = [
      "'/leaderboard'", "'/user-profile'", 'UserProfileScreen', 'LeaderboardScreen',
      'shown to other players',
    ];
    final hits = [
      for (final (path, source) in _libSources())
        for (final word in banned)
          if (source.contains(word)) '$path: $word',
    ];
    expect(hits, isEmpty);
  });

  test('nothing in the app writes a theft alert', () {
    final callers = [
      for (final (path, source) in _libSources())
        if (source.contains('.addTheftAlert(')) path,
    ];
    expect(callers, isEmpty);
  });

  group("the player's own live updates still arrive", () {
    TerritoryRealtimeService connected() =>
        TerritoryRealtimeService(baseUrl: 'http://test.local')..debugConnected = true;

    test('a capture reaches the map with no previous owner in it', () async {
      final service = connected();
      final received = service.onHexChanges.first;

      // The server's payload since B1 part 1: `previousOwnerId` is always null.
      service.debugSimulateHexChanges([
        [
          {
            'h3Index': '8b1', 'centerLat': 12.9, 'centerLng': 77.5, 'newOwnerId': 'me',
            'newOwnerColor': '#123456', 'newOwnerDisplayName': 'Me', 'previousOwnerId': null,
          },
        ],
      ]);

      final events = await received;
      expect(events.single.h3Index, '8b1');
      expect(events.single.previousOwnerId, isNull);
    });

    test('a lost hex leaves the map through the release event', () async {
      final service = connected();
      final received = service.onHexesReleased.first;

      service.debugSimulateHexesReleased([
        {'parentCellId': '7', 'h3Indexes': ['8b1']},
      ]);

      expect((await received).h3Indexes, ['8b1']);
    });
  });
}
