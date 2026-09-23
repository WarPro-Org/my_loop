/// Regression tests for issue #111 — "No snapshot re-fetch on SignalR
/// reconnect — the documented critical resync rule is unimplemented".
///
/// Root cause: `TerritoryRealtimeService`'s `onreconnected` hub callback only
/// re-joined groups (`_resubscribeAll`); nothing told the rest of the app a
/// reconnect happened, so no surface ever re-fetched a snapshot. Missed
/// deltas during the outage were lost forever — a player could keep seeing
/// stats/missions from before the outage, or (worst case, on the map) keep
/// showing territory they'd actually lost.
///
/// The fix adds `TerritoryRealtimeService.onReconnected` (fired once regions
/// are re-joined) and a `realtimeResyncProvider` that re-hydrates every game
/// state slice whenever it fires, plus on every app-foreground resume —
/// connected or not, because the snapshot is a REST fetch.
/// These tests FAIL without the fix (no `onReconnected` stream existed, and
/// nothing consumed it).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/realtime_resync.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/missions_slice.dart';

/// Stand-in [ApiService] whose game-state response is controllable, mirroring
/// the fake used in game_state_offline_cache_test.dart.
class _FakeApi extends ApiService {
  _FakeApi(this.gameState) : super(baseUrl: 'http://localhost');

  final Map<String, dynamic> gameState;

  @override
  Future<Map<String, dynamic>?> getGameState(String userId) async => gameState;
}

/// Real [TerritoryRealtimeService] with a controllable connection state,
/// used to drive `handleReconnected` without a live hub.
class _ControllableRealtime extends TerritoryRealtimeService {
  _ControllableRealtime() : super(baseUrl: 'http://test.local');

  bool connectedOverride = false;

  @override
  bool get isConnected => connectedOverride;
}

/// Real service whose region-join invoke records every attempt and can be
/// made to fail for chosen regions, without a live hub.
class _RejoinRealtime extends TerritoryRealtimeService {
  _RejoinRealtime() : super(baseUrl: 'http://test.local');

  final Set<String> failingRegions = {};
  final List<String> joinAttempts = [];

  @override
  Future<void> invokeJoinRegion(String regionId) async {
    joinAttempts.add(regionId);
    if (failingRegions.contains(regionId)) {
      throw Exception('simulated JoinRegion failure for $regionId');
    }
  }
}

Map<String, dynamic> _mission(String id) => {
      'id': id,
      'type': 0,
      'description': 'Walk 1km',
      'targetValue': 10,
      'currentProgress': 3,
      'xpReward': 50,
      'isCompleted': false,
    };

ProviderContainer _containerWith(ApiService api, TerritoryRealtimeService realtime, String userId) {
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
    territoryRealtimeProvider.overrideWithValue(realtime),
  ]);
  container.read(userProfileProvider.notifier).setFromApi(
        userId: userId,
        avatarId: 0,
        color: '#000000',
        displayName: 'Player',
        hexCount: 0,
        streak: 0,
        distanceKm: 0,
      );
  return container;
}

/// Drives a real foreground transition on the shared binding.
///
/// Both `SchedulerBinding.handleAppLifecycleStateChanged` and
/// `AppLifecycleListener.didChangeAppLifecycleState` ignore a dispatch that
/// repeats the current state, and the listener additionally asserts that
/// `resumed` is only ever entered from `null`/`inactive`/`detached`. Going
/// via `inactive` is therefore the only sequence that actually fires
/// `onResume` — dispatching `resumed` alone is silently a no-op.
void _resumeApp() {
  final binding = TestWidgetsFlutterBinding.instance;
  binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  // realtimeResyncProvider builds an AppLifecycleListener as soon as it's
  // read, even from a plain `test()` block that never pumps a widget — make
  // sure a binding exists up front so that construction doesn't throw.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerritoryRealtimeService.onReconnected', () {
    test('handleReconnected notifies onReconnected listeners exactly once', () async {
      final service = TerritoryRealtimeService(baseUrl: 'http://test.local');
      addTearDown(service.dispose);

      var fireCount = 0;
      final sub = service.onReconnected.listen((_) => fireCount++);
      addTearDown(sub.cancel);

      // No live hub connection needed — the extracted handler is what the
      // real `onreconnected` hub callback now delegates to.
      await service.handleReconnected(connectionId: 'conn-1');
      await pumpEventQueue();

      expect(fireCount, 1);
    });

    test('handleReconnected is safe even if never connected (no hub yet)', () async {
      final service = TerritoryRealtimeService(baseUrl: 'http://test.local');
      addTearDown(service.dispose);

      var fired = false;
      final sub = service.onReconnected.listen((_) => fired = true);
      addTearDown(sub.cancel);

      await service.handleReconnected();
      await pumpEventQueue();

      expect(fired, isTrue);
    });
  });

  group('handleReconnected — a failed region rejoin', () {
    const failing = 'r1';
    const healthy = ['r2', 'r3'];

    Future<_RejoinRealtime> subscribedService() async {
      final service = _RejoinRealtime()..debugConnected = true;
      for (final region in [failing, ...healthy]) {
        await service.joinRegion(region);
      }
      service.joinAttempts.clear();
      service.failingRegions.add(failing);
      return service;
    }

    test('still rejoins the other regions and still fires onReconnected once',
        () async {
      final service = await subscribedService();
      addTearDown(service.dispose);
      var fireCount = 0;
      final sub = service.onReconnected.listen((_) => fireCount++);
      addTearDown(sub.cancel);

      // Must complete normally: the hub invokes this from its onreconnected
      // callback, where nothing awaits or catches the returned future.
      await expectLater(service.handleReconnected(connectionId: 'conn-2'), completes);
      await pumpEventQueue();

      expect(service.joinAttempts, [failing, ...healthy],
          reason: 'one failed rejoin must not abort the rest of the loop');
      expect(service.subscribedRegionsForTest, healthy.toSet());
      expect(fireCount, 1,
          reason: 'listeners resync over REST, which does not need the rejoin');
    });

    test('leaves the failed region unsubscribed so the next update retries it',
        () async {
      final service = await subscribedService();
      addTearDown(service.dispose);

      await service.handleReconnected();
      service.failingRegions.clear();
      await service.updateRegions({failing, ...healthy});

      expect(service.subscribedRegionsForTest, {failing, ...healthy});
    });
  });

  group('realtimeResyncProvider — reconnect resync', () {
    test('a hub reconnect re-hydrates game state slices from a fresh fetch', () async {
      final realtime = _ControllableRealtime();
      addTearDown(realtime.dispose);
      final api = _FakeApi({
        'missions': [_mission('m1')],
        'exploration': [],
      });
      final container = _containerWith(api, realtime, 'u1');
      addTearDown(container.dispose);

      // Establish the wiring (mirrors reading it once at the app root).
      container.read(realtimeResyncProvider);
      expect(container.read(missionsSliceProvider).missions, isEmpty,
          reason: 'nothing hydrated yet — only connecting/reconnecting triggers a fetch');

      await realtime.handleReconnected(connectionId: 'conn-1');
      // Let the async hydration triggered by the reconnect event complete.
      await pumpEventQueue();

      expect(
        container.read(missionsSliceProvider).missions.map((m) => m.id).toSet(),
        {'m1'},
        reason: 'reconnect must re-fetch the snapshot — missed deltas are never replayed',
      );
    });
  });

  group('realtimeResyncProvider — app-foreground resync', () {
    // The lifecycle state lives on the process-wide binding, so a previous
    // test leaving it at `resumed` would make the next resume a no-op.
    setUp(() => TestWidgetsFlutterBinding.instance.resetInternalState());

    test('resuming the app while connected re-hydrates game state', () async {
      final realtime = _ControllableRealtime()..connectedOverride = true;
      addTearDown(realtime.dispose);
      final api = _FakeApi({
        'missions': [_mission('m2')],
        'exploration': [],
      });
      final container = _containerWith(api, realtime, 'u1');
      addTearDown(container.dispose);

      container.read(realtimeResyncProvider);
      expect(container.read(missionsSliceProvider).missions, isEmpty);

      _resumeApp();
      await pumpEventQueue();

      expect(
        container.read(missionsSliceProvider).missions.map((m) => m.id).toSet(),
        {'m2'},
      );
    });

    test('resuming the app while disconnected still re-hydrates', () async {
      // After a long background withAutomaticReconnect has given up and
      // nothing reconnects the hub, so this resume is the only refresh left.
      final realtime = _ControllableRealtime()..connectedOverride = false;
      addTearDown(realtime.dispose);
      final api = _FakeApi({
        'missions': [_mission('m3')],
        'exploration': [],
      });
      final container = _containerWith(api, realtime, 'u1');
      addTearDown(container.dispose);

      container.read(realtimeResyncProvider);

      _resumeApp();
      await pumpEventQueue();

      expect(TestWidgetsFlutterBinding.instance.lifecycleState, AppLifecycleState.resumed,
          reason: 'the resume must really have been delivered, or this asserts nothing');
      expect(
        container.read(missionsSliceProvider).missions.map((m) => m.id).toSet(),
        {'m3'},
        reason: 'the snapshot is GET game-state over REST, not SignalR',
      );
    });
  });
  group('GameStateResync — overlapping triggers', () {
    late List<Completer<void>> fetches;
    late GameStateResync resync;

    setUp(() {
      fetches = [];
      resync = GameStateResync(() {
        final fetch = Completer<void>();
        fetches.add(fetch);
        return fetch.future;
      });
    });

    Future<void> finishFetch(int index) async {
      fetches[index].complete();
      await pumpEventQueue();
    }

    test('a resume during an in-flight fetch joins it', () async {
      resync.onReconnected();
      resync.onResume();
      resync.onResume();
      await finishFetch(0);

      expect(fetches, hasLength(1));
    });

    test('a reconnect during an in-flight fetch queues exactly one follow-up '
        'that starts only after it finishes', () async {
      resync.onResume();
      resync.onReconnected();
      resync.onReconnected();
      expect(fetches, hasLength(1),
          reason: 'the follow-up must not overlap the in-flight fetch');

      await finishFetch(0);
      expect(fetches, hasLength(2),
          reason: 'the first fetch may predate the user-group rejoin');
      await finishFetch(1);

      expect(fetches, hasLength(2));
    });

    test('a failed fetch is logged, not thrown, and the next trigger runs',
        () async {
      resync.onResume();
      fetches[0].completeError(Exception('boom'));
      await pumpEventQueue();

      resync.onResume();
      expect(fetches, hasLength(2));
    });
  });
}
