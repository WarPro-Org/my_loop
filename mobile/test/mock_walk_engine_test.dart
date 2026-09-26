/// Tests for the mock walk simulator engine (#29).
///
/// These lock in the properties that make a simulated walk survive the SAME server
/// anti-cheat the real app faces:
///   • bearing std-dev > 2°  (server rejects spoof-smooth lines),
///   • every hop under the max distance/speed cap,
///   • a loop route actually closes within the client closure threshold.
/// They also pin the failure mode (jitter off ⇒ straight line ⇒ would be rejected),
/// so the realism is a tested guarantee, not an accident.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/services/mock/mock_walk_config.dart';
import 'package:myloop/shared/services/mock/mock_walk_engine.dart';

// Client-side thresholds: imported from the real symbols so they can't silently drift.
final double _closureThresholdMeters = defaultGameRules.loopClosureDistanceMeters;
final int _minLoopPoints = defaultGameRules.minLoopPoints;

// Server-side (C#) thresholds the mock must satisfy. These live in AntiCheatConstants.cs
// and can't be imported into Dart, so they're duplicated here on purpose — a server
// tightening should break this test loudly.
const double _minBearingStdDev = 2.0; // AntiCheatConstants.MinBearingStdDev
const double _maxHopMeters = 60.0; // AntiCheatConstants.MaxDistanceBetweenPointsMeters
const double _maxAverageSpeedMps = 9.0; // AntiCheatConstants.MaxAverageSpeedMetersPerSecond

/// The real moving noise floor the journey controller applies to a mock fix (whose
/// speed is always > stationary threshold): clamp(accuracy, movingMin, movingMax).
final double _noiseFloorMeters = MockWalkConstants.reportedAccuracyMeters
    .clamp(AppConstants.movingNoiseFloorMin, AppConstants.movingNoiseFloorMax);

/// Mirrors the journey controller's noise-floor dedup: drop points closer than the
/// moving noise floor to the last kept point. This is the path the server actually sees.
List<LatLng> _retained(List<MockRoutePoint> raw) {
  final kept = <LatLng>[];
  for (final p in raw) {
    final here = LatLng(p.lat, p.lng);
    if (kept.isEmpty ||
        Geolocator.distanceBetween(kept.last.latitude, kept.last.longitude, here.latitude, here.longitude) >=
            _noiseFloorMeters) {
      kept.add(here);
    }
  }
  return kept;
}

/// Sustained average speed of the path the server actually receives, mirroring
/// `PathValidationService.ValidateConsecutivePoints`: total retained hop distance
/// over total elapsed capturedAt. This is the gate that per-hop checks miss — the
/// per-hop allowance carries a 30 m GPS-drift margin that hides noise-inflated
/// hops, while this average does not.
double _sustainedAverageSpeedMps(List<Position> positions) {
  Position? last;
  var totalMeters = 0.0;
  DateTime? firstAt;
  DateTime? lastAt;
  for (final p in positions) {
    if (last == null) {
      last = p;
      firstAt = p.timestamp;
      lastAt = p.timestamp;
      continue;
    }
    final d = Geolocator.distanceBetween(
        last.latitude, last.longitude, p.latitude, p.longitude);
    if (d < _noiseFloorMeters) continue; // dropped by the client noise floor
    totalMeters += d;
    lastAt = p.timestamp;
    last = p;
  }
  final elapsedSeconds = lastAt!.difference(firstAt!).inMilliseconds / 1000.0;
  return elapsedSeconds <= 0 ? 0 : totalMeters / elapsedSeconds;
}

/// Mirrors the journey controller's noise-floor dedup on timestamped fixes: the
/// retained points are what gets enqueued (capturedAt ≈ fix time) and drained.
List<Position> _retainedPositions(List<Position> raw) {
  final kept = <Position>[];
  for (final p in raw) {
    if (kept.isEmpty ||
        Geolocator.distanceBetween(kept.last.latitude, kept.last.longitude,
                p.latitude, p.longitude) >=
            _noiseFloorMeters) {
      kept.add(p);
    }
  }
  return kept;
}

// Real drain cadence (BatchDrainService): an immediate drain once this many
// points are queued, a periodic timer flushing whatever is queued, and a final
// drainNow() on STOP. Duplicated because the service keeps them private.
const int _drainBatchThreshold = 5; // BatchDrainService._batchThreshold
const int _drainIntervalSeconds = 10; // BatchDrainService._drainIntervalSeconds

/// Average speed of one batch exactly as the server computes it
/// (`ValidateConsecutivePoints`): summed hop distance over first→last capturedAt.
double _batchAverageSpeedMps(List<Position> batch) {
  var meters = 0.0;
  for (var i = 1; i < batch.length; i++) {
    meters += Geolocator.distanceBetween(batch[i - 1].latitude,
        batch[i - 1].longitude, batch[i].latitude, batch[i].longitude);
  }
  final seconds =
      batch.last.timestamp.difference(batch.first.timestamp).inMilliseconds / 1000.0;
  return seconds <= 0 ? 0 : meters / seconds;
}

/// Splits the retained points into the batches the drain service would POST,
/// with its periodic timer firing [timerPhaseSeconds] after the first fix.
List<List<Position>> _drainCadenceBatches(List<Position> kept, int timerPhaseSeconds) {
  final batches = <List<Position>>[];
  var queue = <Position>[];
  void flush() {
    if (queue.isNotEmpty) batches.add(queue);
    queue = <Position>[];
  }

  var nextTick = kept.first.timestamp.add(Duration(seconds: timerPhaseSeconds));
  for (final p in kept) {
    while (!nextTick.isAfter(p.timestamp)) {
      flush();
      nextTick = nextTick.add(const Duration(seconds: _drainIntervalSeconds));
    }
    queue.add(p);
    if (queue.length >= _drainBatchThreshold) flush();
  }
  flush(); // drainNow() on STOP
  return batches;
}

/// Every window the server can be asked to validate as one batch: the real
/// cadence at each timer phase, plus every run of 2..threshold consecutive
/// retained points (a slow drain or a STOP can cut a batch anywhere).
Iterable<List<Position>> _allDrainWindows(List<Position> kept) sync* {
  for (var phase = 0; phase < _drainIntervalSeconds; phase++) {
    yield* _drainCadenceBatches(kept, phase).where((b) => b.length >= 2);
  }
  for (var size = 2; size <= _drainBatchThreshold; size++) {
    for (var i = 0; i + size <= kept.length; i++) {
      yield kept.sublist(i, i + size);
    }
  }
}

/// Worst batch-average speed over every drain window of one plotted walk.
double _worstDrainWindowSpeedMps(MockWalkConfig cfg, int seed) {
  final kept = _retainedPositions(MockWalkEngine(cfg, random: Random(seed))
      .generatePositions(startTime: DateTime(2026, 1, 1)));
  return _allDrainWindows(kept).map(_batchAverageSpeedMps).fold(0.0, max);
}

/// Std-dev of consecutive bearing changes — the server's smoothness metric.
double _bearingChangeStdDev(List<LatLng> path) {
  if (path.length < 3) return 0;
  final changes = <double>[];
  for (var i = 2; i < path.length; i++) {
    final b1 = Geolocator.bearingBetween(
        path[i - 2].latitude, path[i - 2].longitude, path[i - 1].latitude, path[i - 1].longitude);
    final b2 = Geolocator.bearingBetween(
        path[i - 1].latitude, path[i - 1].longitude, path[i].latitude, path[i].longitude);
    var change = b2 - b1;
    while (change > 180) {
      change -= 360;
    }
    while (change < -180) {
      change += 360;
    }
    changes.add(change.abs());
  }
  final mean = changes.reduce((a, b) => a + b) / changes.length;
  final variance = changes.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) / changes.length;
  return sqrt(variance);
}

void main() {
  // Fixed seed so jitter is deterministic and assertions are stable.
  MockWalkEngine engine(MockWalkConfig c) => MockWalkEngine(c, random: Random(42));

  const start = LatLng(37.4220, -122.0841);

  group('loop route', () {
    final raw = engine(const MockWalkConfig(routeType: MockRouteType.loop, startPoint: start)).plotPoints();
    final kept = _retained(raw);

    test('produces enough retained points for a claimable loop', () {
      expect(kept.length, greaterThanOrEqualTo(_minLoopPoints));
    });

    test('closes within the loop closure threshold', () {
      final d = Geolocator.distanceBetween(
          kept.first.latitude, kept.first.longitude, kept.last.latitude, kept.last.longitude);
      expect(d, lessThanOrEqualTo(_closureThresholdMeters));
    });

    test('looks like a human walk: bearing std-dev exceeds the smoothness floor', () {
      expect(_bearingChangeStdDev(kept), greaterThan(_minBearingStdDev));
    });

    test('no hop exceeds the server distance cap', () {
      for (var i = 1; i < raw.length; i++) {
        final d = Geolocator.distanceBetween(raw[i - 1].lat, raw[i - 1].lng, raw[i].lat, raw[i].lng);
        expect(d, lessThan(_maxHopMeters), reason: 'hop $i = ${d}m');
      }
    });
  });

  group('straight route', () {
    test('with jitter still passes the smoothness floor', () {
      final kept = _retained(engine(const MockWalkConfig(
        routeType: MockRouteType.straight,
        startPoint: start,
      )).plotPoints());
      expect(_bearingChangeStdDev(kept), greaterThan(_minBearingStdDev));
    });

    test('WITHOUT jitter is a spoof-smooth line (documents why jitter is required)', () {
      final kept = _retained(engine(const MockWalkConfig(
        routeType: MockRouteType.straight,
        startPoint: start,
        jitterEnabled: false,
      )).plotPoints());
      expect(_bearingChangeStdDev(kept), lessThan(_minBearingStdDev));
    });
  });

  group('multi-waypoint route', () {
    const waypoints = [
      LatLng(37.4220, -122.0841),
      LatLng(37.4232, -122.0841),
      LatLng(37.4232, -122.0825),
    ];
    test('passes near each waypoint in order', () {
      final raw = engine(const MockWalkConfig(
        routeType: MockRouteType.multiWaypoint,
        waypoints: waypoints,
      )).plotPoints();
      for (final wp in waypoints) {
        final nearest = raw
            .map((p) => Geolocator.distanceBetween(p.lat, p.lng, wp.latitude, wp.longitude))
            .reduce(min);
        // Within jitter distance of the waypoint.
        expect(nearest, lessThan(3 * MockWalkConstants.jitterSigmaMeters));
      }
    });

    test('auto-close (default) walks back to the first waypoint so the loop can claim', () {
      final anchors = engine(const MockWalkConfig(
        routeType: MockRouteType.multiWaypoint,
        waypoints: waypoints,
      )).buildRouteAnchors();
      expect(anchors.last, waypoints.first);

      final kept = _retained(engine(const MockWalkConfig(
        routeType: MockRouteType.multiWaypoint,
        waypoints: waypoints,
      )).plotPoints());
      final d = Geolocator.distanceBetween(
          kept.first.latitude, kept.first.longitude, kept.last.latitude, kept.last.longitude);
      expect(d, lessThanOrEqualTo(_closureThresholdMeters));
    });

    test('autoCloseLoop: false leaves the tapped path open', () {
      final anchors = engine(const MockWalkConfig(
        routeType: MockRouteType.multiWaypoint,
        waypoints: waypoints,
        autoCloseLoop: false,
      )).buildRouteAnchors();
      expect(anchors.last, waypoints.last);
    });

    test('an already-closed tapped path is not double-closed', () {
      final anchors = engine(const MockWalkConfig(
        routeType: MockRouteType.multiWaypoint,
        waypoints: [...waypoints, LatLng(37.4220, -122.0841)],
      )).buildRouteAnchors();
      expect(anchors, hasLength(4));
    });
  });

  group('straight route bearing', () {
    test('bearing 90° heads east of the start point', () {
      final anchors = engine(const MockWalkConfig(
        routeType: MockRouteType.straight,
        startPoint: start,
        straightBearingDegrees: 90,
      )).buildRouteAnchors();
      expect(anchors.last.longitude, greaterThan(start.longitude));
      expect((anchors.last.latitude - start.latitude).abs(), lessThan(1e-4));
    });
  });

  group('distance parameterisation (runner contract)', () {
    final e = engine(const MockWalkConfig(
      routeType: MockRouteType.straight,
      startPoint: start,
    ));

    test('totalLengthMeters matches the configured route length', () {
      expect(e.totalLengthMeters,
          closeTo(MockWalkConstants.defaultStraightLengthMeters, 1.0));
    });

    test('cleanPointAt clamps to the route ends', () {
      expect(e.cleanPointAt(-10), e.buildRouteAnchors().first);
      expect(e.cleanPointAt(e.totalLengthMeters + 50), e.buildRouteAnchors().last);
    });

    test('cleanPointAt walks monotonically away from the start', () {
      final origin = e.buildRouteAnchors().first;
      double at(double m) => Geolocator.distanceBetween(origin.latitude,
          origin.longitude, e.cleanPointAt(m).latitude, e.cleanPointAt(m).longitude);
      expect(at(50), closeTo(50, 1.0));
      expect(at(150), closeTo(150, 1.0));
    });
  });

  group('slider extremes stay claimable', () {
    test('loop at minimum radius still yields >= minLoopPoints retained points', () {
      final kept = _retained(engine(const MockWalkConfig(
        routeType: MockRouteType.loop,
        startPoint: start,
        loopRadiusMeters: MockWalkConstants.minLoopRadiusMeters,
      )).plotPoints());
      expect(kept.length, greaterThanOrEqualTo(_minLoopPoints));
    });

    test('straight at minimum length yields >= minGpsPointsPerClaim retained points', () {
      final kept = _retained(engine(const MockWalkConfig(
        routeType: MockRouteType.straight,
        startPoint: start,
        straightLengthMeters: MockWalkConstants.minStraightLengthMeters,
      )).plotPoints());
      expect(kept.length, greaterThanOrEqualTo(AppConstants.minGpsPointsPerClaim));
    });

    test('copyWith clamps an out-of-range radius up to the minimum', () {
      const cfg = MockWalkConfig();
      expect(cfg.copyWith(loopRadiusMeters: 5).loopRadiusMeters,
          MockWalkConstants.minLoopRadiusMeters);
    });
  });

  group('engine memoization', () {
    test('repeated plotPoints calls return the identical (cached) list', () {
      final e = engine(const MockWalkConfig(routeType: MockRouteType.loop, startPoint: start));
      expect(identical(e.plotPoints(), e.plotPoints()), isTrue);
    });
  });

  group('generatePositions', () {
    final positions = engine(const MockWalkConfig(routeType: MockRouteType.loop, startPoint: start))
        .generatePositions(startTime: DateTime(2026, 1, 1));

    test('timestamps are strictly increasing', () {
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i].timestamp.isAfter(positions[i - 1].timestamp), isTrue);
      }
    });

    test('fixes are marked mocked and carry the configured speed', () {
      expect(positions.first.isMocked, isTrue);
      expect(positions.first.speed, MockWalkConstants.defaultSpeedMps);
    });
  });

  // Every one-tap quick-launch scenario must clear the SAME anti-cheat bar as a
  // hand-configured walk. This is the tested guarantee behind the "curated, small,
  // valid-by-construction" claim — a scenario added with bad tuning fails loudly here.
  group('quick-launch scenarios stay anti-cheat-valid by construction', () {
    // The server's per-hop batch gate (PathValidationService): a hop is a violation
    // only when its straight-line distance exceeds what max walking speed could cover
    // in the elapsed capturedAt time, PLUS a GPS-uncertainty margin. Mirrored here so
    // the assertion matches what the backend actually rejects (not a bare d/dt).
    const maxSpeedMps = 8.33; // AntiCheatConstants.MaxSpeedMetersPerSecond
    const gpsDriftMarginMeters = 30.0; // PathValidationService.gpsDriftMarginMeters

    for (final scenario in MockWalkScenarios.all) {
      group(scenario.label, () {
        final cfg = scenario.config.copyWith(startPoint: start);
        final kept = _retained(engine(cfg).plotPoints());

        test('has jitter enabled', () {
          expect(cfg.jitterEnabled, isTrue);
        });

        test('yields retained points above the relevant density floor', () {
          final floor = cfg.routeType == MockRouteType.loop
              ? _minLoopPoints
              : AppConstants.minGpsPointsPerClaim;
          expect(kept.length, greaterThanOrEqualTo(floor));
        });

        test('reads as a human walk (bearing std-dev over the floor)', () {
          expect(_bearingChangeStdDev(kept), greaterThan(_minBearingStdDev));
        });

        if (cfg.routeType == MockRouteType.loop) {
          test('loop closes within the closure threshold', () {
            final d = Geolocator.distanceBetween(kept.first.latitude,
                kept.first.longitude, kept.last.latitude, kept.last.longitude);
            expect(d, lessThanOrEqualTo(_closureThresholdMeters));
          });
        }

        // Model the real flow: fixes are stamped ~1/sec in wall-clock and the client
        // noise floor drops sub-floor hops, so retained capturedAt spacing ≈ tick
        // spacing. A brisk 4 m/s scenario must still keep every retained hop < cap.
        test('every retained hop stays under the server speed cap', () {
          final positions =
              engine(cfg).generatePositions(startTime: DateTime(2026, 1, 1));
          Position? last;
          for (final p in positions) {
            if (last == null) {
              last = p;
              continue;
            }
            final d = Geolocator.distanceBetween(
                last.latitude, last.longitude, p.latitude, p.longitude);
            if (d < _noiseFloorMeters) continue; // dropped by the client noise floor
            final dt = p.timestamp.difference(last.timestamp).inMilliseconds / 1000.0;
            expect(d, lessThanOrEqualTo(maxSpeedMps * dt + gpsDriftMarginMeters),
                reason: '${scenario.label}: ${d}m hop over ${dt}s exceeds the '
                    'server per-hop allowance');
            last = p;
          }
        });
      });
    }
  });

  // The per-hop gate above carries a 30 m GPS-drift margin, so it cannot catch a
  // path whose length is inflated by jitter rather than by teleport jumps. The
  // sustained-average gate can. Whole-walk averages are checked here (with the
  // original independent per-fix jitter at sigma 4.0 m the min-radius loop at max
  // speed measured 9.56 m/s and this group failed); the per-batch windows the
  // server actually validates are checked in the drain-batch group below. Swept
  // over many seeds because a single seed hides the tail.
  group('sustained average speed stays under the server gate', () {
    const seedCount = 40;

    final extremes = <String, MockWalkConfig>{
      'loop at min radius, max speed': const MockWalkConfig(
        routeType: MockRouteType.loop,
        loopRadiusMeters: MockWalkConstants.minLoopRadiusMeters,
        speedMps: MockWalkConstants.maxSpeedMps,
      ),
      'loop at max radius, max speed': const MockWalkConfig(
        routeType: MockRouteType.loop,
        loopRadiusMeters: MockWalkConstants.maxLoopRadiusMeters,
        speedMps: MockWalkConstants.maxSpeedMps,
      ),
      'straight at min length, max speed': const MockWalkConfig(
        routeType: MockRouteType.straight,
        straightLengthMeters: MockWalkConstants.minStraightLengthMeters,
        speedMps: MockWalkConstants.maxSpeedMps,
      ),
      'straight at max length, max speed': const MockWalkConfig(
        routeType: MockRouteType.straight,
        straightLengthMeters: MockWalkConstants.maxStraightLengthMeters,
        speedMps: MockWalkConstants.maxSpeedMps,
      ),
      'loop at min speed': const MockWalkConfig(
        routeType: MockRouteType.loop,
        speedMps: MockWalkConstants.minSpeedMps,
      ),
    };

    for (final entry in extremes.entries) {
      test(entry.key, () {
        final cfg = entry.value.copyWith(startPoint: start);
        for (var seed = 1; seed <= seedCount; seed++) {
          final positions = MockWalkEngine(cfg, random: Random(seed))
              .generatePositions(startTime: DateTime(2026, 1, 1));
          expect(_sustainedAverageSpeedMps(positions), lessThan(_maxAverageSpeedMps),
              reason: '${entry.key}: seed $seed exceeds the sustained-average gate');
        }
      });
    }

    test('every quick-launch scenario clears the gate on every seed', () {
      for (final scenario in MockWalkScenarios.all) {
        final cfg = scenario.config.copyWith(startPoint: start);
        for (var seed = 1; seed <= seedCount; seed++) {
          final positions = MockWalkEngine(cfg, random: Random(seed))
              .generatePositions(startTime: DateTime(2026, 1, 1));
          expect(_sustainedAverageSpeedMps(positions), lessThan(_maxAverageSpeedMps),
              reason: '${scenario.label}: seed $seed exceeds the sustained-average gate');
        }
      }
    });

    // Guards the other side of the sigma trade-off: shrinking jitter to buy speed
    // headroom must not drop a straight route under the smoothness floor.
    test('smoothness floor still cleared at every speed bound', () {
      for (final speed in [
        MockWalkConstants.minSpeedMps,
        MockWalkConstants.defaultSpeedMps,
        MockWalkConstants.maxSpeedMps,
      ]) {
        final cfg = MockWalkConfig(
          routeType: MockRouteType.straight,
          startPoint: start,
          speedMps: speed,
        );
        for (var seed = 1; seed <= seedCount; seed++) {
          final kept = _retained(MockWalkEngine(cfg, random: Random(seed)).plotPoints());
          expect(_bearingChangeStdDev(kept), greaterThan(_minBearingStdDev),
              reason: 'straight at $speed m/s, seed $seed reads as spoof-smooth');
        }
      }
    });
  });

  // The server applies the 9.0 m/s average to EACH batch-step request, not to
  // the whole walk, and the drain sends small batches (2–5 retained points).
  // Independent per-fix jitter survives the 8 m noise floor only when it pushed
  // a fix far, so short windows showed phantom speed: with i.i.d. jitter every
  // config below fails (designer default: 61/200 walks had a batch over the
  // gate at the real cadence, 172/200 counting every 2–5 point window, worst
  // 15.1 m/s). Time-correlated AR(1) jitter keeps all 200 seeds of every config
  // under it (worst 8.5 m/s, quick loop).
  group('every drain batch stays under the sustained-average gate', () {
    const seedCount = 200;
    const midSpeedMps = 2.5;

    final configs = <String, MockWalkConfig>{
      'designer default': const MockWalkConfig(),
      'quick Straight': MockWalkScenarios.straight.config,
      '30 m loop at 2.5 m/s': const MockWalkConfig(
        routeType: MockRouteType.loop,
        loopRadiusMeters: MockWalkConstants.minLoopRadiusMeters,
        speedMps: midSpeedMps,
      ),
      'quick loop': MockWalkScenarios.quickLoop.config,
      'loop at min speed': const MockWalkConfig(
        routeType: MockRouteType.loop,
        speedMps: MockWalkConstants.minSpeedMps,
      ),
    };

    for (final entry in configs.entries) {
      test(entry.key, () {
        final cfg = entry.value.copyWith(startPoint: start);
        for (var seed = 1; seed <= seedCount; seed++) {
          expect(_worstDrainWindowSpeedMps(cfg, seed), lessThan(_maxAverageSpeedMps),
              reason: '${entry.key}: seed $seed has a drain batch over the '
                  'sustained-average gate');
        }
      });
    }

    test('drain-cadence model splits at the threshold, the timer and STOP', () {
      final t0 = DateTime(2026, 1, 1);
      Position at(int s) => engine(const MockWalkConfig()).toPosition(
          const MockRoutePoint(0, 0, 0), t0.add(Duration(seconds: s)), speedMps: 1);
      final kept = [for (final s in [0, 1, 2, 3, 4, 5, 6, 12, 13]) at(s)];
      final sizes = _drainCadenceBatches(kept, _drainIntervalSeconds)
          .map((b) => b.length)
          .toList();
      // 5 queued → immediate drain; the 10 s timer flushes {5, 6}; STOP flushes {12, 13}.
      expect(sizes, [5, 2, 2]);
    });
  });

  group('correlated (AR(1)) jitter', () {
    const metersPerDegLat = 111320.0;
    const fixCount = 20000;
    const tolerance = 0.1; // ±10% of the target statistic over 20k fixes

    List<double> northOffsets(MockWalkEngine e, int count) => [
          for (var i = 0; i < count; i++)
            (e.jitterPoint(start).latitude - start.latitude) * metersPerDegLat,
        ];

    test('keeps the configured stationary spread and fix-to-fix correlation', () {
      final offsets = northOffsets(
          MockWalkEngine(const MockWalkConfig(startPoint: start), random: Random(7)), fixCount);
      final mean = offsets.reduce((a, b) => a + b) / offsets.length;
      final variance =
          offsets.map((o) => (o - mean) * (o - mean)).reduce((a, b) => a + b) / offsets.length;
      var lagCovariance = 0.0;
      for (var i = 1; i < offsets.length; i++) {
        lagCovariance += (offsets[i] - mean) * (offsets[i - 1] - mean);
      }
      final lagCorrelation = lagCovariance / (offsets.length - 1) / variance;

      expect(sqrt(variance),
          closeTo(MockWalkConstants.jitterSigmaMeters, MockWalkConstants.jitterSigmaMeters * tolerance));
      expect(lagCorrelation, closeTo(MockWalkConstants.jitterCorrelation, tolerance));
    });

    test('resetJitter starts a fresh track instead of continuing the last one', () {
      const warmUpFixes = 50;
      const rho = MockWalkConstants.jitterCorrelation;
      // Two engines on the same RNG stream; only one resets before the next fix.
      final continued = MockWalkEngine(const MockWalkConfig(startPoint: start), random: Random(3));
      final reset = MockWalkEngine(const MockWalkConfig(startPoint: start), random: Random(3));
      final previous = northOffsets(continued, warmUpFixes).last;
      northOffsets(reset, warmUpFixes);
      reset.resetJitter();

      final nextContinued = northOffsets(continued, 1).single;
      final nextReset = northOffsets(reset, 1).single;

      // Same Gaussian draw g: continued = ρ·prev + σ·√(1−ρ²)·g, reset = σ·g.
      final g = (nextContinued - rho * previous) /
          (MockWalkConstants.jitterSigmaMeters * sqrt(1 - rho * rho));
      expect(nextReset, closeTo(MockWalkConstants.jitterSigmaMeters * g, 1e-6));
      expect(nextReset, isNot(closeTo(nextContinued, 1e-6)));
    });
  });
}
