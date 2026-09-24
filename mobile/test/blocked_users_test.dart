/// DR-002b / #190 — blocking (App Store Guideline 1.2) on the client.
///
/// Covers: the user-bound block-list cache (codec, disk round-trip, cross-user guard), the
/// provider (API load, offline cold start from cache, optimistic block with rollback), name
/// masking, and report-submission messages.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/theft_alerts.dart';
import 'package:myloop/features/moderation/blocked_users.dart';
import 'package:myloop/features/moderation/player_actions_menu.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/block_list_cache.dart';
import 'package:myloop/shared/services/notification_service.dart';
import 'package:myloop/shared/services/realtime_resync.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// ApiService double for the block/report endpoints only; no request is made.
class _FakeApi extends ApiService {
  Set<String> serverBlocks = {};
  Object? listError;
  /// When set, the list fetch waits for it — simulates a slow (cold-start) response.
  Completer<void>? listGate;
  Object? writeError;
  /// Ids whose block call fails; the rest succeed.
  Set<String> failIds = {};
  /// When set, each block call waits for it — lets two blocks overlap.
  Completer<void>? writeGate;
  String? reportedReason;
  int listCalls = 0;
  /// When true, each list fetch waits on its own completer in [heldLists], in call order.
  bool holdLists = false;
  final List<Completer<void>> heldLists = [];
  /// When true, each block call waits on its own completer in [heldWrites]; completing one with
  /// an error fails that call.
  bool holdWrites = false;
  final List<Completer<void>> heldWrites = [];

  @override
  Future<Set<String>> getBlockedUserIds() async {
    listCalls++;
    if (listError != null) throw listError!;
    final snapshot = {...serverBlocks}; // what the server had when the request was made
    await listGate?.future;
    if (holdLists) {
      final held = Completer<void>();
      heldLists.add(held);
      await held.future;
    }
    return snapshot;
  }

  @override
  Future<void> blockUser(String userId) async {
    if (holdWrites) {
      final held = Completer<void>();
      heldWrites.add(held); // before any await, so the caller sees it synchronously
      await held.future;
    }
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    if (failIds.contains(userId)) throw _status(409, 'refused');
    serverBlocks.add(userId);
  }

  @override
  Future<void> unblockUser(String userId) async {
    if (writeError != null) throw writeError!;
    serverBlocks.remove(userId);
  }

  @override
  Future<void> reportName(String userId, String reason) async {
    if (writeError != null) throw writeError!;
    reportedReason = reason;
  }
}

DioException _unreachable() => DioException(
      requestOptions: RequestOptions(path: '/api'),
      type: DioExceptionType.unknown,
      error: const SocketException('Connection refused'),
    );

DioException _status(int code, String message) {
  final request = RequestOptions(path: '/api');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: code, data: message),
  );
}

void main() {
  late Directory tmp;
  late StreamController<ResyncTrigger> resyncTriggers;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('block_list_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    resyncTriggers = StreamController<ResyncTrigger>.broadcast();
  });

  tearDown(() async {
    await resyncTriggers.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// A container signed in as [userId], with the block provider already listened to.
  ProviderContainer signedIn(_FakeApi api, {String userId = 'me'}) {
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      territoryRealtimeProvider.overrideWithValue(TerritoryRealtimeService(baseUrl: 'http://test.local')),
      resyncTriggersProvider.overrideWithValue(resyncTriggers.stream),
    ]);
    addTearDown(container.dispose);
    container.listen(blockedUsersProvider, (_, _) {});
    container.read(userProfileProvider.notifier).setFromApi(
          userId: userId, avatarId: 0, color: '#00D4AA', displayName: 'Robin',
        );
    return container;
  }

  /// Lets the provider's async cache/API load finish.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('BlockListCache', () {
    test('codec round-trips and rejects another user or garbage', () {
      final raw = BlockListCache.encode('me', {'a', 'b'});
      expect(BlockListCache.decode(raw, 'me'), {'a', 'b'});
      expect(BlockListCache.decode(raw, 'someone-else'), isNull);
      expect(BlockListCache.decode('not json', 'me'), isNull);
    });

    test('what save writes is exactly what load reads, until clear', () async {
      await BlockListCache.save('me', {'a', 'b'});
      expect(await BlockListCache.load('me'), {'a', 'b'});
      expect(await BlockListCache.load('other'), isNull);
      await BlockListCache.clear();
      expect(await BlockListCache.load('me'), isNull);
    });

    test('an empty user id is never cached', () async {
      await BlockListCache.save('', {'a'});
      expect(await BlockListCache.load(''), isNull);
    });
  });

  group('blockedUsersProvider', () {
    test('loads the block list from the API and caches it', () async {
      final api = _FakeApi()..serverBlocks = {'rival'};
      final container = signedIn(api);
      await settle();

      expect(container.read(blockedUsersProvider), {'rival'});
      expect(await BlockListCache.load('me'), {'rival'});
    });

    test('an offline cold start restores the cached list (masking survives no network)', () async {
      await BlockListCache.save('me', {'rival'});
      final container = signedIn(_FakeApi()..listError = _unreachable());
      await settle();

      expect(container.read(blockedUsersProvider), {'rival'});
    });

    test("another account's cached list is never applied", () async {
      await BlockListCache.save('previous-user', {'rival'});
      final container = signedIn(_FakeApi()..listError = _unreachable());
      await settle();

      expect(container.read(blockedUsersProvider), isEmpty);
    });

    test('block masks immediately, persists, and unblock reverses it', () async {
      final api = _FakeApi();
      final container = signedIn(api);
      await settle();

      expect(await container.read(blockedUsersProvider.notifier).block('rival'), isNull);
      expect(container.read(blockedUsersProvider), {'rival'});
      expect(api.serverBlocks, {'rival'});
      expect(await BlockListCache.load('me'), {'rival'});

      expect(await container.read(blockedUsersProvider.notifier).unblock('rival'), isNull);
      expect(container.read(blockedUsersProvider), isEmpty);
    });

    test('a slow sign-in fetch cannot undo a block made while it was in flight', () async {
      final api = _FakeApi()..listGate = Completer<void>();
      final container = signedIn(api);
      await settle(); // fetch is now in flight, holding the pre-block (empty) list

      await container.read(blockedUsersProvider.notifier).block('rival');
      api.listGate!.complete();
      await settle();

      expect(container.read(blockedUsersProvider), {'rival'});
      expect(await BlockListCache.load('me'), {'rival'});
    });

    test("a block made during a slow load keeps the server's existing blocks too", () async {
      final api = _FakeApi()
        ..serverBlocks = {'a', 'b'}
        ..listGate = Completer<void>();
      final container = signedIn(api);
      await settle(); // fetch in flight, holding {a, b}

      await container.read(blockedUsersProvider.notifier).block('x');
      api.listGate!.complete();
      await settle();

      expect(container.read(blockedUsersProvider), {'a', 'b', 'x'});
      expect(await BlockListCache.load('me'), {'a', 'b', 'x'});
    });

    test('a failed edit restores an earlier successful edit to the same player', () async {
      // Block succeeds, an offline unblock fails, then the slow sign-in fetch (started before the
      // block, so it holds the old empty list) lands: the player must stay blocked.
      final api = _FakeApi()..listGate = Completer<void>();
      final container = signedIn(api);
      await settle(); // fetch in flight, holding {}

      final notifier = container.read(blockedUsersProvider.notifier);
      expect(await notifier.block('rival'), isNull);
      api.writeError = _unreachable();
      expect(await notifier.unblock('rival'), blockOfflineError);
      expect(container.read(blockedUsersProvider), {'rival'});

      api.listGate!.complete();
      await settle();

      expect(container.read(blockedUsersProvider), {'rival'});
      expect(await BlockListCache.load('me'), {'rival'});
    });

    test('a first load that failed offline is retried on resume or reconnect', () async {
      final api = _FakeApi()..listError = _unreachable();
      final container = signedIn(api);
      await settle();
      expect(container.read(blockedUsersProvider), isEmpty);

      api
        ..listError = null
        ..serverBlocks = {'rival'};
      resyncTriggers.add(ResyncTrigger.resume);
      await settle();

      expect(container.read(blockedUsersProvider), {'rival'});
      expect(await BlockListCache.load('me'), {'rival'});
    });

    test('once a fetch has succeeded, resume and reconnect do not re-fetch', () async {
      final api = _FakeApi();
      signedIn(api);
      await settle();
      expect(api.listCalls, 1);

      resyncTriggers
        ..add(ResyncTrigger.resume)
        ..add(ResyncTrigger.reconnect);
      await settle();

      expect(api.listCalls, 1);
    });

    test('a failed block rolls back only its own id, not an overlapping one', () async {
      final api = _FakeApi()
        ..failIds = {'first'}
        ..writeGate = Completer<void>();
      final container = signedIn(api);
      await settle();

      final notifier = container.read(blockedUsersProvider.notifier);
      final first = notifier.block('first');
      final second = notifier.block('second');
      api.writeGate!.complete();
      await Future.wait([first, second]);

      expect(container.read(blockedUsersProvider), {'second'});
    });

    test('a refused block rolls back and returns the server reason', () async {
      final api = _FakeApi()..writeError = _status(409, "You've blocked the maximum number of players");
      final container = signedIn(api);
      await settle();

      final error = await container.read(blockedUsersProvider.notifier).block('rival');

      expect(error, "You've blocked the maximum number of players");
      expect(container.read(blockedUsersProvider), isEmpty);
    });

    test('blocking offline rolls back and says why', () async {
      final container = signedIn(_FakeApi()..writeError = _unreachable());
      await settle();

      expect(await container.read(blockedUsersProvider.notifier).block('rival'), blockOfflineError);
      expect(container.read(blockedUsersProvider), isEmpty);
    });

    test('a failed edit does not undo a newer edit to the same player still in flight', () async {
      final api = _FakeApi()..holdWrites = true;
      final container = signedIn(api);
      await settle();

      final notifier = container.read(blockedUsersProvider.notifier);
      final first = notifier.block('rival');
      final second = notifier.block('rival');
      expect(api.heldWrites, hasLength(2));

      api.heldWrites[0].completeError(_status(409, 'refused'));
      expect(await first, 'refused');
      expect(container.read(blockedUsersProvider), {'rival'}); // the second block is still pending

      api.heldWrites[1].complete();
      expect(await second, isNull);
      expect(container.read(blockedUsersProvider), {'rival'});
      expect(await BlockListCache.load('me'), {'rival'});
    });

    test("a previous account's slow fetch never lands in the next account's list", () async {
      // Riverpod 3 keeps the Notifier instance across a rebuild, so account A's in-flight fetch
      // resumes on the notifier that now serves account B (#195 review).
      final api = _FakeApi()
        ..serverBlocks = {'blocked-by-a'}
        ..holdLists = true;
      final container = signedIn(api, userId: 'a');
      await settle();
      expect(api.heldLists, hasLength(1)); // A's fetch in flight

      container.read(userProfileProvider.notifier).clear();
      await settle();
      api.serverBlocks = {'blocked-by-b'};
      container.read(userProfileProvider.notifier).setFromApi(
            userId: 'b', avatarId: 0, color: '#00D4AA', displayName: 'Kai',
          );
      await settle();
      expect(api.heldLists, hasLength(2)); // B's fetch in flight

      var bReleased = false;
      final forB = container.read(blockedUsersProvider.notifier).blockedIdsFor('b')
        ..then((_) => bReleased = true);

      api.heldLists[0].complete(); // A's fetch lands after the switch
      await settle();

      expect(bReleased, isFalse, reason: "A's load must not finish B's first load");
      expect(container.read(blockedUsersProvider), isEmpty);
      expect(await BlockListCache.load('a'), isNull, reason: "A's list must not be re-cached after sign-out");

      api.heldLists[1].complete();
      expect(await forB, {'blocked-by-b'});
      expect(container.read(blockedUsersProvider), {'blocked-by-b'});
    });

    test("a previous account's in-flight block is not applied to the next account", () async {
      final api = _FakeApi()..holdWrites = true;
      final container = signedIn(api, userId: 'a');
      await settle();

      final pending = container.read(blockedUsersProvider.notifier).block('rival');
      container.read(userProfileProvider.notifier).clear();
      await BlockListCache.clear(); // what sign-out's teardown does
      await settle();
      container.read(userProfileProvider.notifier).setFromApi(
            userId: 'b', avatarId: 0, color: '#00D4AA', displayName: 'Kai',
          );
      await settle();

      api.heldWrites.single.complete();
      expect(await pending, isNull);
      await settle();

      expect(container.read(blockedUsersProvider), isEmpty);
      expect(await BlockListCache.load('a'), isNull);
      expect(await BlockListCache.load('b'), isEmpty); // B's own fetch result, untouched by A's edit
    });

    test('signing out empties the list', () async {
      final container = signedIn(_FakeApi()..serverBlocks = {'rival'});
      await settle();

      container.read(userProfileProvider.notifier).clear();

      expect(container.read(blockedUsersProvider), isEmpty);
    });
  });

  group('theft alerts right after sign-in', () {
    HexChangeEvent stolenBy(String thiefId, String thiefName) => HexChangeEvent(
          h3Index: '8a2a1072b59ffff', centerLat: 0, centerLng: 0,
          newOwnerId: thiefId, newOwnerColor: '#FF4B4B', newOwnerDisplayName: thiefName,
          previousOwnerId: 'me',
        );

    Future<List<String>> alertBodies(ProviderContainer container, List<HexChangeEvent> events) async {
      final notifications = container.read(notificationProvider.notifier);
      await notifications.hydration;
      await recordTheftAlerts(
        userId: 'me',
        events: events,
        blockedUsers: container.read(blockedUsersProvider.notifier),
        notifications: notifications,
      );
      await notifications.pendingWrite;
      return container.read(notificationProvider).map((n) => n.body).toList();
    }

    test('a theft the moment the session starts masks a blocked thief from the cached list', () async {
      // Cold start: the block list is on disk, the API is slow, and a theft event arrives before
      // the provider has restored anything — its state is still the empty initial set.
      await BlockListCache.save('me', {'rival'});
      final container = signedIn(_FakeApi()..listGate = Completer<void>());

      final bodies = await alertBodies(container, [stolenBy('rival', 'Rude Name'), stolenBy('kai', 'Kai')]);

      expect(bodies, containsAll(['$blockedActorLabel captured 1 of your hex!', 'Kai captured 1 of your hex!']));
      expect(bodies.join(), isNot(contains('Rude Name')));
    });

    test('with no cached list, the alert waits for the first fetch', () async {
      final api = _FakeApi()
        ..serverBlocks = {'rival'}
        ..listGate = Completer<void>();
      final container = signedIn(api);

      final recorded = alertBodies(container, [stolenBy('rival', 'Rude Name')]);
      await settle();
      api.listGate!.complete();

      expect(await recorded, ['$blockedActorLabel captured 1 of your hex!']);
    });
  });

  group('masking', () {
    test('displayNameFor hides only blocked players', () {
      expect(displayNameFor({'rival'}, 'rival', 'Rude Name'), blockedPlayerLabel);
      expect(displayNameFor({'rival'}, 'friend', 'Kai'), 'Kai');
    });

    test('the hex popup withholds other names while the block list is unknown', () {
      expect(hexOwnerNameFor({'rival'}, 'me', 'rival', 'Rude Name'), blockedPlayerLabel);
      expect(hexOwnerNameFor({'rival'}, 'me', 'kai', 'Kai'), 'Kai');
      expect(hexOwnerNameFor(null, 'me', 'rival', 'Rude Name'), blockedActorLabel);
      expect(hexOwnerNameFor(null, 'me', 'me', 'Robin'), 'Robin');
    });

    test('a masked map cell keeps everything but the owner name', () {
      const cell = TerritoryCell(
          cellId: 1, ownerId: 'rival', ownerColor: '#FF4B4B', boundary: [], ownerName: 'Rude Name',
          parentCellId: 9, decayProgress: 0.5);
      final maskedCell = cell.withOwnerName(blockedPlayerLabel);
      expect([maskedCell.ownerName, maskedCell.ownerId, maskedCell.parentCellId, maskedCell.decayProgress],
          [blockedPlayerLabel, 'rival', 9, 0.5]);
    });
  });

  group('submitNameReport', () {
    test('sends the wire value and thanks the player', () async {
      final api = _FakeApi();
      expect(await submitNameReport(api, 'rival', NameReportReason.impersonation), reportThanksMessage);
      expect(api.reportedReason, 'impersonation');
    });

    test('shows the server reason for a refused report', () async {
      final api = _FakeApi()..writeError = _status(429, "You've reached today's report limit");
      expect(await submitNameReport(api, 'rival', NameReportReason.offensive), "You've reached today's report limit");
    });

    test('offline says so', () async {
      final api = _FakeApi()..writeError = _unreachable();
      expect(await submitNameReport(api, 'rival', NameReportReason.other), reportOfflineError);
    });
  });
}
