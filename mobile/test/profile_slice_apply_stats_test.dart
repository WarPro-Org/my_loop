/// Regression tests for PR #172 review round 1, findings 2 and 5.
///
/// `profileSliceProvider` is the sole owner of game stats (#113), and several
/// callers seed it with only part of them:
///   * login, dev skip and the avatar picker pass a `User`'s hex count, streak
///     and distance, which carries no totals, streak flag or rank;
///   * game-state reports `rank: 0` when its rank query failed.
/// Neither may zero the fields it did not supply.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/state/profile_slice.dart';

const _liveRank = 3;

ProviderContainer _containerWithFullStats() {
  final container = ProviderContainer();
  container.read(profileSliceProvider.notifier).hydrate({
    'hexCount': 100,
    'totalHexesCaptured': 120,
    'totalHexesStolen': 7,
    'streak': 4,
    'isStreakActive': true,
    'distanceKm': 12.5,
    'rank': _liveRank,
  });
  return container;
}

void main() {
  test('applyStats keeps every field the caller did not pass', () {
    final container = _containerWithFullStats();
    addTearDown(container.dispose);

    container.read(profileSliceProvider.notifier).applyStats(
          hexCount: 140,
          streak: 5,
          distanceKm: 13,
        );

    final stats = container.read(profileSliceProvider);
    expect(stats.hexCount, 140);
    expect(stats.streak, 5);
    expect(stats.distanceKm, 13);
    expect(stats.totalHexesCaptured, 120);
    expect(stats.totalHexesStolen, 7);
    expect(stats.isStreakActive, isTrue);
    expect(stats.rank, _liveRank);
    expect(stats.isLoaded, isTrue);
  });

  test('hydrate keeps the current rank when game-state reports 0 or none', () {
    final container = _containerWithFullStats();
    addTearDown(container.dispose);
    final slice = container.read(profileSliceProvider.notifier);

    slice.hydrate({'hexCount': 140, 'rank': 0});
    expect(container.read(profileSliceProvider).rank, _liveRank);
    expect(container.read(profileSliceProvider).hexCount, 140);

    slice.hydrate({'hexCount': 150});
    expect(container.read(profileSliceProvider).rank, _liveRank);

    slice.hydrate({'hexCount': 150, 'rank': 42});
    expect(container.read(profileSliceProvider).rank, 42);
  });
}
