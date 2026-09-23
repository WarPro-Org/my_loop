/// Regression test for the Home-stats half of issue #111 (PR #177 review
/// round 2, finding 2).
///
/// SignalR never replays a `UserStatsDelta` pushed while the socket was down,
/// so after an outage the Home quick stats (hexes, streak, rank) stay at their
/// pre-outage values unless a snapshot re-fetch reaches what the tiles read.
/// Since #172 the tiles read `profileSliceProvider` — the sole owner of stats —
/// and `realtimeResyncProvider` re-hydrates that slice on every reconnect and
/// resume. This test pumps the real `HomeTab` and drives both triggers through
/// the production `realtimeResyncProvider`, asserting on the rendered tiles,
/// so a regression in either the wiring or what the tiles read fails here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/home/home_tab.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/realtime_resync.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_slice.dart';

const _staleHexes = 1111;
const _staleStreak = 23;
const _staleRank = 9;

const _freshHexes = 4242;
const _freshStreak = 37;
const _freshRank = 7;

/// Past `HomeTab`'s first-load shimmer, so the quick-stats row is mounted.
const _pastShimmer = Duration(milliseconds: 700);

/// Serves the post-outage game-state snapshot.
class _FreshGameStateApi extends ApiService {
  _FreshGameStateApi() : super(baseUrl: 'http://localhost');

  int gameStateFetches = 0;

  @override
  Future<Map<String, dynamic>?> getGameState(String userId) async {
    gameStateFetches++;
    return {
      'hexCount': _freshHexes,
      'streak': _freshStreak,
      'rank': _freshRank,
      'missions': const [],
      'achievements': const [],
      'exploration': const [],
    };
  }
}

void main() {
  late _FreshGameStateApi api;
  late TerritoryRealtimeService realtime;
  late ProviderContainer container;

  /// Builds the provider graph inside the test body, so every stream
  /// subscription lives in the test's fake-async zone and `tester.pump`
  /// delivers its events.
  void buildWorld() {
    api = _FreshGameStateApi();
    realtime = TerritoryRealtimeService(baseUrl: 'http://test.local');
    container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      territoryRealtimeProvider.overrideWithValue(realtime),
    ]);
    container.read(userProfileProvider.notifier).setFromApi(
          userId: 'u1',
          avatarId: 0,
          color: '#000000',
          displayName: 'Player',
        );
    // Pre-outage stats, as the last live push or sign-in left them.
    container.read(profileSliceProvider.notifier).applyStats(
          hexCount: _staleHexes,
          streak: _staleStreak,
          rank: _staleRank,
        );
    // Wired once at the app root in production (MyLoopApp).
    container.read(realtimeResyncProvider);
    addTearDown(() {
      container.dispose();
      realtime.dispose();
    });
  }

  // The lifecycle state lives on the process-wide binding, so a previous
  // test leaving it at `resumed` would make the next resume a no-op.
  setUp(() => TestWidgetsFlutterBinding.instance.resetInternalState());

  Future<void> pumpHome(WidgetTester tester) async {
    buildWorld();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: HomeTab()),
        ),
      ),
    );
    await tester.pump(_pastShimmer);
    expect(find.text('$_staleHexes'), findsWidgets);
    expect(find.text('$_staleStreak'), findsOneWidget);
    expect(find.text(rankLabel(_staleRank)), findsOneWidget);
  }

  void expectFreshTiles() {
    expect(api.gameStateFetches, 1);
    expect(find.text('$_freshHexes'), findsWidgets);
    expect(find.text('$_freshStreak'), findsOneWidget);
    expect(find.text(rankLabel(_freshRank)), findsOneWidget);
    expect(find.text('$_staleHexes'), findsNothing);
    expect(find.text('$_staleStreak'), findsNothing);
    expect(find.text(rankLabel(_staleRank)), findsNothing);
  }

  Future<void> unmount(WidgetTester tester) async {
    // Home has repeat() animation controllers; unmount so no ticker or timer
    // is left pending at teardown (#71).
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('a hub reconnect updates the Home quick stats and rank',
      (tester) async {
    await pumpHome(tester);

    await realtime.handleReconnected(connectionId: 'conn-2');
    await tester.pump();

    expectFreshTiles();
    await unmount(tester);
  });

  testWidgets('an app resume updates the Home quick stats and rank, even with '
      'the hub disconnected', (tester) async {
    await pumpHome(tester);
    expect(realtime.isConnected, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expectFreshTiles();
    await unmount(tester);
  });
}
