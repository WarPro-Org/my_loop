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
///
/// Round 2 of the review added: a walk started (or still starting) while
/// sign-out runs must not survive it; sign-out cancels an in-flight batch
/// rather than waiting on the network; a session Firebase ends behind the UI
/// is torn down too; and a failed server delete keeps the session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
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

/// Generous bound for a sign-out that must not wait on the network.
const _promptTeardown = Duration(seconds: 5);

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

  /// Gated batches that were cancelled before the server answered.
  int cancelledBatches = 0;

  /// When set, the reachability probe blocks until it completes.
  Completer<void>? reachGate;

  @override
  Future<bool> isServerReachable() async {
    final pending = reachGate;
    if (pending != null) await pending.future;
    return true;
  }

  @override
  Future<BatchResult?> claimBatchStep({
    required String userId,
    required String localDate,
    required String walkSessionId,
    required List<QueuedStepPoint> points,
    CancelToken? cancelToken,
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
      // Like Dio: a cancel ends the wait, and the real claimBatchStep maps a
      // cancel to null (covered in batch_drain_service_test.dart).
      await Future.any([
        pending.future,
        if (cancelToken != null) cancelToken.whenCancel,
      ]);
      if (cancelToken?.isCancelled ?? false) {
        cancelledBatches++;
        return null;
      }
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

  /// When true, the server delete fails (offline / 5xx).
  bool failDelete = false;

  @override
  Future<void> deleteAccount(String userId) async {
    if (failDelete) {
      throw DioException(requestOptions: RequestOptions(path: '/api/users/$userId'));
    }
    deletedAccounts.add(userId);
  }
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

  /// When true, Firebase refuses the delete (e.g. needs recent re-auth).
  bool failFirebaseDelete = false;

  /// Drives [authStateChanges] by hand, e.g. a token revoked elsewhere.
  final authStates = StreamController<User?>.broadcast();

  @override
  Future<void> deleteCurrentUser() async {
    if (failFirebaseDelete) throw StateError('requires-recent-login');
    deleteCalls++;
    _api.signedInAs = null;
  }

  @override
  User? get currentUser => null;

  @override
  Stream<User?> get authStateChanges => authStates.stream;

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

  /// When set, the permission prompt blocks until it completes.
  Completer<void>? permissionGate;

  @override
  Future<bool> requestPermission() async {
    final pending = permissionGate;
    if (pending != null) await pending.future;
    return true;
  }

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

/// Signs a test account in with identity fields only, so these tests don't
/// depend on which stats `setFromApi` carries (#172 moves stats out of it).
class _TestProfile extends UserProfileNotifier {
  void signIn(String userId) => state = UserProfile(userId: userId, displayName: userId);
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

  Future<void> walk(int steps) async {
    for (var i = 0; i < steps; i++) {
      loc.gps.add(loc.next());
    }
    await _settle();
  }

  void signIn(String userId) {
    api.signedInAs = userId;
    (container.read(userProfileProvider.notifier) as _TestProfile).signIn(userId);
  }

  /// Asserts nothing of the previous session is left running or queued.
  void expectNoLiveWalk(String userId) {
    expect(loc.gps.hasListener, isFalse, reason: 'GPS subscription must be cancelled');
    expect(container.read(journeyControllerProvider).status, JourneyStatus.idle);
    expect(journey().pendingQueueSize, 0, reason: 'queue memory must be empty');
    expect(onDisk(userId), isEmpty, reason: 'queue disk must be empty');
  }

  /// After [next] signs in and the device keeps moving, no batch sent under
  /// [next]'s token may carry a point from any walk other than its own.
  Future<void> expectNoLeakInto(String next, Set<String> foreignWalks) async {
    signIn(next);
    await walk(_drainThreshold * 2);
    for (final claim in api.claims.where((c) => c.owner == next)) {
      expect(foreignWalks, isNot(contains(claim.walkSessionId)),
          reason: "$next's token carried a previous account's walk");
    }
    expect(api.claims.where((c) => c.owner == next), isEmpty,
        reason: 'no walk was started for $next, so nothing may drain under its token');
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
      userProfileProvider.overrideWith(_TestProfile.new),
    ]);
  });

  tearDown(() async {
    journey().stopJourney();
    container.dispose();
    await loc.gps.close();
    await auth.authStates.close();
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
    // Sign-out cancelled the in-flight batch; a response arriving afterwards
    // must not rewrite the WAL.
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

    expect(await session().deleteAccount(), isTrue);
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

  // ── Round-2 review finding 1: interleavings of startJourney with sign-out ──

  test('a walk started while sign-out waits on an in-flight drain is torn down too',
      () async {
    signIn(_userA);
    await journey().startJourney();
    final walkA = journey().walkSessionId!;
    final serverResponse = Completer<void>();
    api.gate = serverResponse;
    await walk(_drainThreshold);
    await _until(() => api.claims.length == 1);

    // Sign-out has begun and is waiting on that batch (before the cancel fix it
    // waited until the server answered). The user stops and restarts a walk.
    final signingOut = session().signOut();
    journey().stopJourney();
    await journey().startJourney();
    final restarted = journey().walkSessionId;
    await walk(2);

    if (!serverResponse.isCompleted) serverResponse.complete();
    await signingOut;
    await _settle();

    expectNoLiveWalk(_userA);
    await expectNoLeakInto(_userB, {walkA, ?restarted});
    expectNoLiveWalk(_userA);
  });

  test('signing out during the reachability probe stops the walk from starting', () async {
    signIn(_userA);
    final probe = Completer<void>();
    api.reachGate = probe;
    final starting = journey().startJourney();
    await _settle();

    await session().signOut();
    probe.complete();
    await starting;
    await _settle();

    expectNoLiveWalk(_userA);
    await expectNoLeakInto(_userB, const {});
    expectNoLiveWalk(_userB);
  });

  test('signing out during the permission prompt stops the walk from starting', () async {
    signIn(_userA);
    final prompt = Completer<void>();
    loc.permissionGate = prompt;
    final starting = journey().startJourney();
    await _settle();

    await session().signOut();
    prompt.complete();
    await starting;
    await _settle();

    expectNoLiveWalk(_userA);
    await expectNoLeakInto(_userB, const {});
    expectNoLiveWalk(_userB);
  });

  // ── Round-2 review finding 2: sign-out cancels instead of waiting ──

  test('sign-out cancels an in-flight batch instead of waiting for the server', () async {
    signIn(_userA);
    await journey().startJourney();
    // The server never answers this batch (offline, slow network).
    api.gate = Completer<void>();
    await walk(_drainThreshold);
    await _until(() => api.claims.length == 1);

    await session().signOut().timeout(_promptTeardown);

    expect(api.cancelledBatches, 1);
    expect(auth.signOutCalls, 1);
    expectNoLiveWalk(_userA);
  });

  // ── Round-2 review finding 3: session ended outside the app ──

  test('Firebase ending the session mid-walk, with no UI involved, tears the walk down',
      () async {
    container.read(forcedSignOutGuardProvider);
    signIn(_userA);
    await journey().startJourney();
    final walkA = journey().walkSessionId!;
    await walk(_drainThreshold - 1);
    expect(onDisk(_userA), isNotEmpty);

    // E.g. the account was deleted on another device: Firebase emits null and
    // the router redirects to /login without calling the teardown.
    api.signedInAs = null;
    auth.authStates.add(null);
    await _settle();

    expectNoLiveWalk(_userA);
    expect(container.read(userProfileProvider).userId, isNull);
    expect(realtime.disconnectCalls, 1);
    await expectNoLeakInto(_userB, {walkA});
  });

  test('a UI sign-out does not run the teardown a second time when Firebase emits null',
      () async {
    container.read(forcedSignOutGuardProvider);
    signIn(_userA);

    await session().signOut();
    auth.authStates.add(null);
    await _settle();

    expect(realtime.disconnectCalls, 1);
  });

  // ── Round-2 review finding 4: App Store 5.1.1(v) ──

  test('a failed server delete keeps the account signed in and reports failure', () async {
    signIn(_userA);
    api.failDelete = true;

    expect(await session().deleteAccount(), isFalse);

    expect(auth.signOutCalls, 0, reason: 'must not look like the account is gone');
    expect(auth.deleteCalls, 0);
    expect(container.read(userProfileProvider).userId, _userA);
    expect(realtime.disconnectCalls, 0);
    expect(api.deletedAccounts, isEmpty);
  });

  test('a Firebase delete failure after the server delete still ends the session', () async {
    signIn(_userA);
    auth.failFirebaseDelete = true;

    expect(await session().deleteAccount(), isTrue);

    expect(api.deletedAccounts, [_userA]);
    expect(auth.signOutCalls, 1);
    expect(container.read(userProfileProvider).userId, isNull);
  });
}
