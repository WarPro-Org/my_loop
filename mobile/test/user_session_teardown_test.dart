/// Regression tests for #110 review finding 1: signing out mid-walk must tear
/// down the LIVE step-claim write layer, not clear the WAL through a second
/// queue instance.
///
/// Pre-fix, sign-out cleared the file via a fresh `StepClaimQueue` while the
/// journey controller's own instance kept its in-memory points, GPS
/// subscription and drain timer. A drain ACK or GPS point after sign-out then
/// re-wrote the outgoing account's file, and — because the server takes the
/// claim owner from the JWT — the next drain after another account signed in
/// claimed the previous account's GPS points as the new account's territory.
///
/// These drive the real JourneyController → StepClaimQueue → BatchDrainService
/// wiring against a temp documents directory; only the network, GPS and auth
/// edges are faked. The fake API records which account's token each batch was
/// sent under, mirroring how the server attributes claims.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myloop/features/auth/user_session_teardown.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/batch_drain_service.dart';
import 'package:myloop/shared/services/location_service.dart';
import 'package:myloop/shared/services/step_claim_queue.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _userA = 'user-a';
const _userB = 'user-b';

/// BatchDrainService drains immediately once this many points are queued.
const _drainThreshold = 5;

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// One batch as the server would attribute it: [owner] is the account whose
/// token was on the request (null = signed out), not the body's userId.
class _Claim {
  _Claim(this.owner, this.walkSessionId, this.clientIds);
  final String? owner;
  final String walkSessionId;
  final List<String> clientIds;
}

class _FakeApi extends ApiService {
  /// The account whose Firebase token the auth interceptor would attach.
  String? signedInAs;
  final claims = <_Claim>[];
  final deletedAccounts = <String>[];

  /// When set, the next batch blocks until it completes — an in-flight drain.
  Completer<void>? gate;

  /// How many of a gated batch's points the server ACKs.
  int? ackFirst;

  @override
  Future<bool> isServerReachable() async => true;

  @override
  Future<BatchResult?> claimBatchStep({
    required String userId,
    required String localDate,
    required String walkSessionId,
    required List<QueuedStepPoint> points,
  }) async {
    claims.add(_Claim(
      signedInAs,
      walkSessionId,
      points.map((p) => p.clientId).toList(),
    ));
    final pending = gate;
    final ack = ackFirst;
    if (pending != null) {
      gate = null;
      ackFirst = null;
      await pending.future;
    }
    final acked = ack == null ? points : points.take(ack);
    return BatchResult(
      results: acked
          .map((p) => BatchPointResult(
                clientId: p.clientId,
                claimed: false,
                wasStolen: false,
              ))
          .toList(),
      stats: BatchStats.fromJson(const {}),
      xp: BatchXp.fromJson(const {}),
      missions: const [],
      achievements: const [],
    );
  }

  @override
  Future<void> deleteAccount(String userId) async => deletedAccounts.add(userId);
}

class _FakeAuth implements AuthService {
  _FakeAuth(this._api);
  final _FakeApi _api;
  int signOutCalls = 0;
  int deleteCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _api.signedInAs = null;
  }

  @override
  Future<void> deleteCurrentUser() async {
    deleteCalls++;
    _api.signedInAs = null;
  }

  @override
  User? get currentUser => null;

  @override
  Stream<User?> get authStateChanges => const Stream.empty();

  @override
  Future<User?> signInWithGoogle() async => null;

  @override
  Future<User?> signInWithApple() async => null;
}

/// GPS the test drives by hand. The stream stays open across sign-out, as the
/// real OS stream would while the phone is still being carried.
class _FakeLocation extends LocationService {
  final gps = StreamController<Position>.broadcast();

  /// When set, getCurrentPosition blocks until it completes.
  Completer<void>? fixGate;
  var _step = 0;

  Position next() {
    _step++;
    return Position(
      // ~33 m per step: well above the moving noise floor, so every point queues.
      latitude: 51.5 + _step * 0.0003,
      longitude: -0.12,
      timestamp: DateTime.now(),
      accuracy: 5,
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
  Future<Position> getCurrentPosition() async {
    final pending = fixGate;
    if (pending != null) await pending.future;
    return next();
  }

  @override
  Stream<Position> startTracking() => gps.stream;
}

class _FakeRealtime extends TerritoryRealtimeService {
  _FakeRealtime() : super(baseUrl: 'http://test.local');
  int disconnectCalls = 0;

  @override
  Future<void> disconnect() async => disconnectCalls++;
}

/// Lets real file I/O and microtasks run.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 150));

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition not reached in time');
}

void main() {
  late Directory tmp;
  late _FakeApi api;
  late _FakeAuth auth;
  late _FakeLocation loc;
  late _FakeRealtime realtime;
  late ProviderContainer container;

  JourneyController journey() => container.read(journeyControllerProvider.notifier);
  UserSessionTeardown session() => container.read(userSessionTeardownProvider);

  File walFile(String userId) =>
      File('${tmp.path}/step_claim_queue_$userId.jsonl');

  /// Points on disk for [userId], read straight from the file so the read has
  /// no side effects. A missing file counts as empty.
  List<QueuedStepPoint> onDisk(String userId) {
    final file = walFile(userId);
    if (!file.existsSync()) return const [];
    return file
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map((l) => QueuedStepPoint.fromJson(jsonDecode(l) as Map<String, dynamic>))
        .toList();
  }

  void signIn(String userId) {
    api.signedInAs = userId;
    container.read(userProfileProvider.notifier).setFromApi(
          userId: userId,
          avatarId: 0,
          color: '#FF0000',
          displayName: userId,
          hexCount: 0,
          streak: 0,
          distanceKm: 0,
        );
  }

  Future<void> walk(int steps) async {
    for (var i = 0; i < steps; i++) {
      loc.gps.add(loc.next());
    }
    await _settle();
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('user_session_teardown_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    api = _FakeApi();
    auth = _FakeAuth(api);
    loc = _FakeLocation();
    realtime = _FakeRealtime();
    container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      authServiceProvider.overrideWithValue(auth),
      locationServiceProvider.overrideWithValue(loc),
      territoryRealtimeProvider.overrideWithValue(realtime),
    ]);
  });

  tearDown(() async {
    journey().stopJourney();
    container.dispose();
    await loc.gps.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
      'sign-out mid-walk with a drain in flight leaves disk and memory empty, '
      'and no later ACK, GPS point or drain brings the points back', () async {
    signIn(_userA);
    await journey().startJourney();
    expect(container.read(journeyControllerProvider).status, JourneyStatus.tracking);

    // Reaching the threshold starts a drain; the server holds the response.
    final serverResponse = Completer<void>();
    api.gate = serverResponse;
    api.ackFirst = 2;
    await walk(_drainThreshold);
    await _until(() => api.claims.length == 1);
    await walk(2);
    expect(journey().pendingQueueSize, _drainThreshold + 2);

    final signingOut = session().signOut();
    await _settle();
    // The in-flight batch's ACK lands mid-teardown and triggers a WAL rewrite.
    serverResponse.complete();
    final inFlight = api.claims.length;
    await signingOut;
    await _settle();

    expect(auth.signOutCalls, 1);
    expect(journey().pendingQueueSize, 0, reason: 'live queue memory must be empty');
    expect(onDisk(_userA), isEmpty, reason: 'disk must agree with memory: nothing survives');
    expect(container.read(journeyControllerProvider).status, JourneyStatus.idle);
    expect(loc.gps.hasListener, isFalse, reason: 'GPS subscription must be cancelled');

    // The phone is still moving: none of this may reach the queue or network.
    await walk(_drainThreshold * 2);
    expect(onDisk(_userA), isEmpty);
    expect(journey().pendingQueueSize, 0);
    expect(api.claims.length, inFlight, reason: 'no batch may be sent after sign-out');
  });

  test("the next account's claims and queue never contain the previous account's points",
      () async {
    signIn(_userA);
    await journey().startJourney();
    final walkA = journey().walkSessionId;
    await walk(_drainThreshold - 2); // below threshold: stays queued, undrained
    final pointsA = onDisk(_userA).map((p) => p.clientId).toSet();
    expect(pointsA, hasLength(_drainThreshold - 2));

    await session().signOut();
    signIn(_userB);
    // B hasn't started a walk yet, but the device keeps reporting positions.
    await walk(_drainThreshold);

    await journey().startJourney();
    final walkB = journey().walkSessionId;
    expect(walkB, isNot(walkA));
    await walk(_drainThreshold);
    await _until(() => api.claims.any((c) => c.owner == _userB));

    for (final claim in api.claims.where((c) => c.owner == _userB)) {
      expect(claim.walkSessionId, walkB, reason: "B's token must only carry B's walk");
      expect(claim.clientIds.toSet().intersection(pointsA), isEmpty);
    }
    expect(onDisk(_userB).every((p) => p.walkSessionId == walkB), isTrue);
    expect(onDisk(_userB).length, journey().pendingQueueSize, reason: 'disk == memory');
    expect(onDisk(_userA), isEmpty);
  });

  test('deleting the account mid-walk clears the queue before the server delete', () async {
    signIn(_userA);
    await journey().startJourney();
    await walk(_drainThreshold - 1);
    expect(onDisk(_userA), isNotEmpty);

    await session().deleteAccount();
    await walk(_drainThreshold);

    expect(api.deletedAccounts, [_userA]);
    expect(auth.deleteCalls, 1);
    expect(onDisk(_userA), isEmpty);
    expect(journey().pendingQueueSize, 0);
    expect(realtime.disconnectCalls, 1);
    expect(container.read(userProfileProvider).userId, isNull);
    expect(api.claims, isEmpty);
  });

  test('sign-out with no walk this session clears a leftover WAL from an earlier run',
      () async {
    final leftover = StepClaimQueue();
    await leftover.init(_userA);
    await leftover.enqueue(QueuedStepPoint(
      clientId: 'killed-mid-walk',
      lat: 1,
      lng: 2,
      capturedAt: DateTime.utc(2026, 9, 1),
      walkSessionId: 'old-walk',
    ));
    signIn(_userA);

    await session().signOut();

    expect(onDisk(_userA), isEmpty);
    expect(realtime.disconnectCalls, 1);
    expect(auth.signOutCalls, 1);
    expect(container.read(userProfileProvider).userId, isNull);
  });

  test('a disk error clearing the queue does not abort sign-out', () async {
    signIn(_userA);
    await journey().startJourney();
    await walk(2);
    // Make the queue's atomic rewrite fail: its temp path is now a directory.
    await Directory('${walFile(_userA).path}.tmp').create();

    await session().signOut();

    expect(auth.signOutCalls, 1, reason: 'Firebase sign-out must still run');
    expect(realtime.disconnectCalls, 1);
    expect(container.read(userProfileProvider).userId, isNull);
    expect(journey().pendingQueueSize, 0);
    expect(container.read(journeyControllerProvider).status, JourneyStatus.idle);
  });

  test('a walk still starting when the account signs out never attaches its write layer',
      () async {
    signIn(_userA);
    loc.fixGate = Completer<void>();
    final starting = journey().startJourney();
    await _settle();

    await session().signOut();
    loc.fixGate!.complete();
    await starting;
    await walk(_drainThreshold);

    expect(loc.gps.hasListener, isFalse);
    expect(container.read(journeyControllerProvider).status, JourneyStatus.idle);
    expect(onDisk(_userA), isEmpty);
    expect(api.claims, isEmpty);
  });
}
