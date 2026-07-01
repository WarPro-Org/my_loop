/// MyLoop — Mock Walk Simulation: injectable location source (#29)
///
/// A drop-in stand-in for [LocationService] that feeds the simulated walk into the
/// exact same journey flow a real walk uses (loop detection → WAL queue → batch
/// drain → server anti-cheat → DB → SignalR). It `implements` the real service's
/// public surface, so the analyzer fails the build if that contract drifts.
///
/// Only ever constructed by `locationServiceProvider` under `kDebugMode` while the
/// simulator is enabled — unreachable in release builds.
library;

import 'package:geolocator/geolocator.dart';

import '../location_service.dart';
import 'mock_walk_engine.dart';
import 'mock_walk_config.dart';
import 'mock_walk_progress.dart';

class MockLocationService implements LocationService {
  final MockWalkEngine _engine;

  /// Optional, debug-only progress sink for the dev HUD. Read-only observer —
  /// the values it receives never feed back into the emitted stream. Null in any
  /// path that does not surface progress (e.g. unit tests of the raw stream).
  final MockWalkProgressNotifier? _progress;

  MockLocationService(MockWalkConfig config, [this._progress])
      : _engine = MockWalkEngine(config);

  /// The simulator never needs real OS permission.
  @override
  Future<bool> requestPermission() async => true;

  /// One-shot fix = the first plotted point of the route (the walk's start point).
  @override
  Future<Position> getCurrentPosition() async =>
      _engine.generatePositions(startTime: DateTime.now()).first;

  /// Streams the simulated walk, reporting progress to [_progress] as it goes:
  /// `begin` with the total plotted-fix count, a `tick` per emitted fix, and
  /// `finish` when the stream ends (whether it completes or is cancelled on stop).
  @override
  Stream<Position> startTracking() async* {
    _progress?.begin(_engine.plotPoints().length);
    try {
      await for (final position in _engine.stream()) {
        _progress?.tick();
        yield position;
      }
    } finally {
      _progress?.finish();
    }
  }

  /// No OS resources to release — the journey controller owns and cancels the
  /// stream subscription returned by [startTracking].
  @override
  void dispose() {}
}
