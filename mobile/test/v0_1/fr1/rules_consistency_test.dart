/// FR1 — the app uses consistent rules in every situation: while walking, when it comes back
/// online, after sign-out, and after a crash in the middle of saving.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/game_rules_provider.dart';
import 'package:myloop/shared/rules/rules_source.dart';
import 'package:myloop/shared/rules/rules_store.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/location_service.dart';
import 'package:myloop/shared/services/realtime_resync.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _lenientAccuracyMeters = 50.0;
const _strictAccuracyMeters = 20.0;
const _fixAccuracyMeters = 30.0; // accepted by the lenient rules, rejected by the strict ones

SavedRules _rules(int version,
        {double accuracy = _lenientAccuracyMeters, int? minLoopPoints}) =>
    SavedRules(
      GameRules.fromJson({
        ...defaultGameRules.toJson(),
        'version': version,
        'gpsAccuracyThresholdMeters': accuracy,
        'minLoopPoints': ?minLoopPoints,
      }),
      'tag-$version',
    );

class _MemoryStore implements RulesStore {
  _MemoryStore([this.saved]);
  SavedRules? saved;

  /// Holds load() open until completed, like a slow disk right after launch.
  Completer<void>? slowLoad;
  @override
  Future<SavedRules?> load() async {
    await slowLoad?.future;
    return saved;
  }
  @override
  Future<void> save(SavedRules rules) async => saved = rules;
}

/// Serves whatever [current] is, and counts requests.
class _SwitchableSource implements RulesSource {
  _SwitchableSource(this.current);
  SavedRules current;
  int fetches = 0;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    fetches++;
    return current.tag == knownTag ? null : current;
  }
}

class _OfflineSource implements RulesSource {
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async =>
      throw DioException(requestOptions: RequestOptions(path: '/api/rules'));
}

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');
  int previews = 0;
  @override
  Future<PreviewResult> previewClaim({required List<List<double>> path}) async {
    previews++;
    return const PreviewResult(boundaries: [], loopCount: 1);
  }
  @override
  Future<bool> isServerReachable() async => true;
  @override
  Future<Map<String, dynamic>?> getGameState(String userId) async => null;
}

class _FakeRealtime extends TerritoryRealtimeService {
  _FakeRealtime() : super(baseUrl: 'http://test.local');
  @override
  Future<void> disconnect() async {}
}

class _FakeLocation extends LocationService {
  final gps = StreamController<Position>.broadcast();
  var _step = 0;

  /// A fix ~33 m further north each time, so every one clears the noise floor.
  Position next({double accuracy = 5}) {
    _step++;
    return _at(51.5 + _step * 0.0003, -0.12, accuracy);
  }

  static const _loopCentreLat = 51.5;
  static const _loopCentreLng = -0.12;
  static const _loopRadiusDegrees = 0.00135; // ~150 m
  static const loopSteps = 25; // ~38 m apart: above the noise floor, back to the start at the end

  /// Point [k] of a circle walked from due east; point 0 and point [loopSteps] are the same.
  Position onLoop(int k) {
    final angle = 2 * math.pi * k / loopSteps;
    return _at(
      _loopCentreLat + _loopRadiusDegrees * math.sin(angle),
      _loopCentreLng + _loopRadiusDegrees * math.cos(angle) / math.cos(_loopCentreLat * math.pi / 180),
      5,
    );
  }

  Position? startAt;

  Position _at(double latitude, double longitude, double accuracy) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 1.5,
      speedAccuracy: 0,
    );
  }

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Position> getCurrentPosition() async => startAt ?? next();
  @override
  Stream<Position> startTracking() => gps.stream;
}

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

ProviderContainer _container(RulesSource source,
    {_FakeLocation? location, _MemoryStore? store, _FakeApi? api}) {
  final container = ProviderContainer(overrides: [
    rulesStoreProvider.overrideWithValue(store ?? _MemoryStore()),
    rulesSourceProvider.overrideWithValue(source),
    apiServiceProvider.overrideWithValue(api ?? _FakeApi()),
    territoryRealtimeProvider.overrideWithValue(_FakeRealtime()),
    if (location != null) locationServiceProvider.overrideWithValue(location),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<GameRules> _rulesSettled(ProviderContainer container) async {
  container.read(gameRulesProvider);
  await container.read(gameRulesProvider.notifier).refresh();
  return container.read(gameRulesProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a walk keeps the rules it started with; the next walk uses the new ones', () async {
    final source = _SwitchableSource(_rules(1));
    final location = _FakeLocation();
    final container = _container(source, location: location);
    expect((await _rulesSettled(container)).gpsAccuracyThresholdMeters, _lenientAccuracyMeters);
    final journey = container.read(journeyControllerProvider.notifier);

    await journey.startJourney();
    final pointsAtStart = container.read(journeyControllerProvider).path.length;

    // The server tightens the GPS accuracy rule in the middle of the walk.
    source.current = _rules(2, accuracy: _strictAccuracyMeters);
    await container.read(gameRulesProvider.notifier).refresh();
    expect(container.read(gameRulesProvider).gpsAccuracyThresholdMeters, _strictAccuracyMeters);

    location.gps.add(location.next(accuracy: _fixAccuracyMeters));
    await pumpEventQueue();
    expect(container.read(journeyControllerProvider).path.length, pointsAtStart + 1,
        reason: 'this walk started under the lenient rules, so the 30 m fix still counts');

    journey.stopJourney();
    await journey.startJourney();
    final second = container.read(journeyControllerProvider);
    expect(second.status, JourneyStatus.tracking);
    expect(second.error, isNull);
    location.gps.add(location.next());
    await pumpEventQueue();
    final pointsBeforeFix = container.read(journeyControllerProvider).path.length;
    expect(pointsBeforeFix, second.path.length + 1, reason: 'the second walk is recording');

    location.gps.add(location.next(accuracy: _fixAccuracyMeters));
    await pumpEventQueue();
    expect(container.read(journeyControllerProvider).path.length, pointsBeforeFix,
        reason: 'the next walk uses the strict rules, so the 30 m fix is ignored');
    journey.stopJourney();
  });

  test('a walk keeps its loop rules when new ones arrive mid-walk', () async {
    final source = _SwitchableSource(_rules(1));
    final location = _FakeLocation()..startAt = _FakeLocation().onLoop(0);
    final api = _FakeApi();
    final container = _container(source, location: location, api: api);
    await _rulesSettled(container);
    final journey = container.read(journeyControllerProvider.notifier);
    await journey.startJourney();

    // Mid-walk the server demands far more points per loop than this walk will have.
    source.current = _rules(2, minLoopPoints: 1000);
    await container.read(gameRulesProvider.notifier).refresh();
    expect(container.read(gameRulesProvider).minLoopPoints, 1000);

    for (var k = 1; k <= _FakeLocation.loopSteps; k++) {
      location.gps.add(location.onLoop(k));
      await pumpEventQueue();
    }

    expect(container.read(journeyControllerProvider).path.length, _FakeLocation.loopSteps + 1);
    expect(api.previews, greaterThan(0),
        reason: 'the walk started with a 20-point minimum, so closing the circle is a loop');
    journey.stopJourney();
  });

  test('a walk started right after launch waits for the saved rules', () async {
    final store = _MemoryStore(_rules(6, accuracy: _strictAccuracyMeters))
      ..slowLoad = Completer<void>();
    final location = _FakeLocation();
    // No rules from the server at launch (offline): only the saved copy can tell the app.
    final container = _container(_OfflineSource(), location: location, store: store);
    final journey = container.read(journeyControllerProvider.notifier);

    final starting = journey.startJourney();
    await pumpEventQueue();
    store.slowLoad!.complete();
    await starting;

    expect(container.read(journeyControllerProvider).status, JourneyStatus.tracking);
    final pointsAtStart = container.read(journeyControllerProvider).path.length;
    location.gps.add(location.next(accuracy: _fixAccuracyMeters));
    await pumpEventQueue();
    expect(container.read(journeyControllerProvider).path.length, pointsAtStart,
        reason: 'the saved strict rules (v6) apply, not the built-in lenient ones');
    journey.stopJourney();
  });

  group('coming back online', () {
    ProviderContainer signedIn(_SwitchableSource source) {
      final container = _container(source);
      container.read(userProfileProvider.notifier).setFromApi(
            userId: 'user-1',
            avatarId: 0,
            color: '#000000',
            displayName: 'Player',
          );
      return container;
    }

    test('a reconnect after being offline checks the rules again', () async {
      final source = _SwitchableSource(_rules(1));
      final container = signedIn(source);
      await _rulesSettled(container);
      container.read(realtimeResyncProvider);
      final before = source.fetches;

      source.current = _rules(2);
      await container.read(territoryRealtimeProvider).handleReconnected();
      await pumpEventQueue();

      expect(source.fetches, greaterThan(before));
      expect(container.read(gameRulesProvider).version, 2);
    });

    test('returning to the app checks the rules again', () async {
      final source = _SwitchableSource(_rules(1));
      final container = signedIn(source);
      await _rulesSettled(container);
      container.read(realtimeResyncProvider);
      final before = source.fetches;

      source.current = _rules(2);
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(source.fetches, greaterThan(before));
      expect(container.read(gameRulesProvider).version, 2);
    });
  });

  test('signing out keeps the rules the app already has', () async {
    final source = _SwitchableSource(_rules(3));
    final container = _container(source);
    await _rulesSettled(container);
    container.read(userProfileProvider.notifier).setFromApi(
          userId: 'user-1',
          avatarId: 0,
          color: '#000000',
          displayName: 'Player',
        );

    await container.read(userSessionTeardownProvider).clearUserBoundState();

    expect(container.read(userProfileProvider).userId, isNull);
    expect(container.read(gameRulesProvider).version, 3,
        reason: 'rules are not tied to a user; sign-out must not drop back to older rules');
  });

  group('crash in the middle of saving', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fr1_rules_crash');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('a save cut off before it finishes never replaces the saved copy, and the next save works',
        () async {
      await FileRulesStore().save(_rules(4));
      // The app dies after writing the new copy but before swapping it in.
      final crashing = FileRulesStore(
          replace: (tmp, path) async => throw const FileSystemException('app killed'));
      await expectLater(crashing.save(_rules(5)), throwsA(isA<FileSystemException>()));

      final afterCrash = await FileRulesStore().load();
      expect(afterCrash?.rules.version, 4, reason: 'the saved copy was never touched');

      await FileRulesStore().save(_rules(5));
      final afterNextSave = await FileRulesStore().load();
      expect(afterNextSave?.rules.version, 5);
      expect(File('${tempDir.path}/game_rules.json.tmp').existsSync(), isFalse);
    });
  });
}
