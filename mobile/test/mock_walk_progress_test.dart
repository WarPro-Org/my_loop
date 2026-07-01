/// Tests for the mock-walk live progress notifier (#29 follow-up).
///
/// The notifier is the single source of truth for the debug HUD/summary, so these
/// pin its state transitions: a run begins with a known total, ticks accumulate,
/// finishing is terminal without disturbing counts, and a fresh begin (or reset)
/// can never leak a prior run's totals into the next HUD/ETA.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/mock/mock_walk_config.dart';
import 'package:myloop/shared/services/mock/mock_walk_progress.dart';

void main() {
  late ProviderContainer container;
  MockWalkProgressNotifier notifier() =>
      container.read(mockWalkProgressProvider.notifier);
  MockWalkProgress state() => container.read(mockWalkProgressProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('starts idle and inactive', () {
    expect(state().isActive, isFalse);
    expect(state().fraction, 0);
    expect(state().eta, Duration.zero);
  });

  test('begin activates the run with the given total', () {
    notifier().begin(10);
    expect(state().isActive, isTrue);
    expect(state().total, 10);
    expect(state().emitted, 0);
    expect(state().finished, isFalse);
    expect(state().startedAt, isNotNull);
  });

  test('tick accumulates emitted and drives fraction', () {
    notifier().begin(4);
    notifier().tick();
    notifier().tick();
    expect(state().emitted, 2);
    expect(state().fraction, 0.5);
  });

  test('eta maps remaining fixes to the tick interval', () {
    notifier().begin(10);
    notifier().tick();
    expect(state().eta, MockWalkConstants.tickInterval * 9);
  });

  test('finish is terminal and preserves counts', () {
    notifier().begin(3);
    notifier().tick();
    notifier().finish();
    expect(state().finished, isTrue);
    expect(state().emitted, 1);
    expect(state().total, 3);
  });

  test('a new begin clears the previous run (no stale totals)', () {
    notifier().begin(5);
    notifier().tick();
    notifier().finish();
    notifier().begin(8);
    expect(state().emitted, 0);
    expect(state().total, 8);
    expect(state().finished, isFalse);
  });

  test('reset returns to the idle state', () {
    notifier().begin(5);
    notifier().tick();
    notifier().reset();
    expect(state().isActive, isFalse);
    expect(state().emitted, 0);
  });

  test('fraction is clamped to 1 even if emitted somehow exceeds total', () {
    notifier().begin(1);
    notifier().tick();
    notifier().tick();
    expect(state().fraction, 1.0);
    expect(state().eta, Duration.zero);
  });
}
