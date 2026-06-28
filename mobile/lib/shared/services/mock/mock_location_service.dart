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

class MockLocationService implements LocationService {
  final MockWalkEngine _engine;

  MockLocationService(MockWalkConfig config) : _engine = MockWalkEngine(config);

  /// The simulator never needs real OS permission.
  @override
  Future<bool> requestPermission() async => true;

  /// One-shot fix = the first plotted point of the route (the walk's start point).
  @override
  Future<Position> getCurrentPosition() async =>
      _engine.generatePositions(startTime: DateTime.now()).first;

  @override
  Stream<Position> startTracking() => _engine.stream();

  /// No OS resources to release — the journey controller owns and cancels the
  /// stream subscription returned by [startTracking].
  @override
  void dispose() {}
}
