/// MyLoop — Mock Walk Simulation: live run progress (#29 follow-up)
///
/// Debug-only, read-only telemetry for an in-flight simulated walk. The
/// [MockLocationService] reports `begin` once it knows the plotted fix count,
/// then `tick`s per emitted fix and `finish`es when the stream completes; the
/// dev HUD and post-run summary read this to show progress and a result.
///
/// This NEVER feeds back into the position stream or `capturedAt` — it only
/// observes. The real [LocationService] never touches it, and nothing reads or
/// writes it outside `kDebugMode`-gated widgets, so it is inert in release.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock_walk_config.dart';

/// Immutable snapshot of a simulated walk's progress.
class MockWalkProgress {
  /// Total fixes the engine will emit for this run (0 = no run started yet).
  final int total;

  /// Fixes emitted so far. Always `<= total`.
  final int emitted;

  /// Wall-clock start of the run, used to compute elapsed time.
  final DateTime? startedAt;

  /// True once the stream has completed (the simulated walk reached its end).
  final bool finished;

  const MockWalkProgress({
    this.total = 0,
    this.emitted = 0,
    this.startedAt,
    this.finished = false,
  });

  /// True once [begin] has been called for a run (whether or not it has ended).
  bool get isActive => total > 0;

  /// Completion fraction in `[0, 1]`.
  double get fraction => total == 0 ? 0 : (emitted / total).clamp(0.0, 1.0);

  /// Time since the run started, or [Duration.zero] before it began.
  Duration get elapsed =>
      startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  /// Estimated time remaining. Fixes are emitted one per
  /// [MockWalkConstants.tickInterval] in real wall-clock time, so the remaining
  /// fixes map directly to remaining seconds.
  Duration get eta =>
      MockWalkConstants.tickInterval * (total - emitted).clamp(0, total);
}

/// Tracks progress of the active simulated walk. Reset at the start of each run
/// so a previous walk's totals can never leak into the next one's HUD/ETA.
class MockWalkProgressNotifier extends Notifier<MockWalkProgress> {
  @override
  MockWalkProgress build() => const MockWalkProgress();

  /// Start a new run with a known total fix count. Clears any prior state.
  void begin(int total) => state = MockWalkProgress(
        total: total,
        emitted: 0,
        startedAt: DateTime.now(),
        finished: false,
      );

  /// Record one emitted fix.
  void tick() => state = MockWalkProgress(
        total: state.total,
        emitted: state.emitted + 1,
        startedAt: state.startedAt,
        finished: state.finished,
      );

  /// Mark the run complete (stream ended).
  void finish() => state = MockWalkProgress(
        total: state.total,
        emitted: state.emitted,
        startedAt: state.startedAt,
        finished: true,
      );

  /// Return to the idle, no-run state.
  void reset() => state = const MockWalkProgress();
}

final mockWalkProgressProvider =
    NotifierProvider<MockWalkProgressNotifier, MockWalkProgress>(
        MockWalkProgressNotifier.new);
