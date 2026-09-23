/// Regression tests for PR #171 round 3 — the Home rank tile after sign-in and
/// onboarding.
///
/// Game-state hydration used to fill only the slices and never wrote the rank
/// the Home tile read. So:
///   * a relaunch kept the rank sign-in seeded from the un-refreshed leaderboard
///     snapshot (and cached it in [ProfileCache]);
///   * a new player's tile read "#0" until their first walk.
/// [hydrateAndSyncProfileRank] makes game-state the single source of that rank.
/// Since #113 the Home tile reads `profileSliceProvider` (the sole owner of
/// game stats), so these tests assert on the slice.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/home/home_tab.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/profile_cache.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/state/profile_rank_sync.dart';
import 'package:myloop/shared/state/profile_slice.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _userId = 'user-1';
const _firebaseUid = 'fb-uid-1';

/// Rank the leaderboard snapshot still held when sign-in used to seed from it.
const _snapshotRank = 5;

/// Live rank game-state reports.
const _liveRank = 3;

/// Points [ProfileCache] and the offline home-card cache at a temp dir.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Game-state reports [gameStateRank]; `reachable: false` makes it fail (offline).
class _FakeApi extends ApiService {
  _FakeApi({required this.gameStateRank, this.reachable = true})
      : super(baseUrl: 'http://localhost');

  final int gameStateRank;
  final bool reachable;

  @override
  Future<Map<String, dynamic>?> getGameState(String userId) async =>
      reachable ? {'hexCount': 0, 'streak': 0, 'distanceKm': 0, 'rank': gameStateRank} : null;
}

/// Pumps a widget exposing a real [WidgetRef], with the profile set as sign-in
/// or registration leaves it (holding [seedRank]).
Future<(WidgetRef, ProviderContainer)> _pumpWithProfile(
  WidgetTester tester,
  ApiService api, {
  required int seedRank,
}) async {
  late WidgetRef captured;
  await tester.pumpWidget(ProviderScope(
    overrides: [apiServiceProvider.overrideWithValue(api)],
    child: Consumer(builder: (context, ref, _) {
      captured = ref;
      return const SizedBox.shrink();
    }),
  ));
  final container = ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
  container.read(userProfileProvider.notifier).setFromApi(
        userId: _userId,
        avatarId: 0,
        color: '#000000',
        displayName: 'Player',
      );
  container.read(profileSliceProvider.notifier).applyStats(
        hexCount: 0,
        streak: 0,
        distanceKm: 0,
        rank: seedRank,
      );
  return (captured, container);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('profile_rank_sync_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('sign-in: live game-state rank replaces a stale snapshot rank, in memory and in ProfileCache',
      (tester) async {
    final (ref, container) =
        await _pumpWithProfile(tester, _FakeApi(gameStateRank: _liveRank), seedRank: _snapshotRank);
    // Sign-in caches the profile before hydrating (login_screen.dart).
    await tester.runAsync(() => cacheSignedInProfile(ref, _firebaseUid));

    await tester.runAsync(() => hydrateAndSyncProfileRank(
          ref,
          isMounted: () => true,
          cacheForFirebaseUid: _firebaseUid,
        ));

    expect(container.read(profileSliceProvider).rank, _liveRank);
    final cached = await tester.runAsync(ProfileCache.load);
    expect(cached?.firebaseUid, _firebaseUid);
    expect(cached?.rank, _liveRank,
        reason: 'an offline relaunch must restore the live rank, not the snapshot');
  });

  testWidgets('onboarding: a new player gets game-state rank instead of 0', (tester) async {
    const newPlayerRank = 7;
    final (ref, container) =
        await _pumpWithProfile(tester, _FakeApi(gameStateRank: newPlayerRank), seedRank: 0);

    await tester.runAsync(() => hydrateAndSyncProfileRank(ref, isMounted: () => true));

    expect(container.read(profileSliceProvider).rank, newPlayerRank);
  });

  testWidgets('a game-state rank of 0 keeps the current rank', (tester) async {
    final (ref, container) =
        await _pumpWithProfile(tester, _FakeApi(gameStateRank: 0), seedRank: _liveRank);

    final applied =
        await tester.runAsync(() => hydrateAndSyncProfileRank(ref, isMounted: () => true));

    expect(applied, isTrue);
    expect(container.read(profileSliceProvider).rank, _liveRank);
  });

  testWidgets('unreachable game-state changes nothing and caches nothing', (tester) async {
    final (ref, container) = await _pumpWithProfile(
        tester, _FakeApi(gameStateRank: _liveRank, reachable: false),
        seedRank: _snapshotRank);

    final applied = await tester.runAsync(() => hydrateAndSyncProfileRank(
          ref,
          isMounted: () => true,
          cacheForFirebaseUid: _firebaseUid,
        ));

    expect(applied, isFalse);
    expect(container.read(profileSliceProvider).rank, _snapshotRank);
    expect(await tester.runAsync(ProfileCache.load), isNull);
  });

  testWidgets('a sign-out during hydration neither copies the rank nor re-creates the cache',
      (tester) async {
    final (ref, container) =
        await _pumpWithProfile(tester, _FakeApi(gameStateRank: _liveRank), seedRank: 0);

    final applied = await tester.runAsync(() {
      final pending = hydrateAndSyncProfileRank(
        ref,
        isMounted: () => true,
        cacheForFirebaseUid: _firebaseUid,
      );
      // Sign-out mid-flight, as the Home drawer / Profile screen do it.
      container.read(userProfileProvider.notifier).clear();
      container.invalidate(profileSliceProvider);
      return pending;
    });

    expect(applied, isFalse);
    expect(container.read(profileSliceProvider).rank, 0);
    expect(await tester.runAsync(ProfileCache.load), isNull);
  });

  test('the Home rank label never reads "#0"', () {
    expect(rankLabel(3), '#3');
    expect(rankLabel(0), '—');
  });
}
