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
import 'package:myloop/features/moderation/blocked_users.dart';
import 'package:myloop/features/moderation/player_actions_menu.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/block_list_cache.dart';
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

  @override
  Future<Set<String>> getBlockedUserIds() async {
    if (listError != null) throw listError!;
    final snapshot = {...serverBlocks}; // what the server had when the request was made
    await listGate?.future;
    return snapshot;
  }

  @override
  Future<void> blockUser(String userId) async {
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

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('block_list_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// A container signed in as [userId], with the block provider already listened to.
  ProviderContainer signedIn(_FakeApi api, {String userId = 'me'}) {
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      territoryRealtimeProvider.overrideWithValue(TerritoryRealtimeService(baseUrl: 'http://test.local')),
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

    test('signing out empties the list', () async {
      final container = signedIn(_FakeApi()..serverBlocks = {'rival'});
      await settle();

      container.read(userProfileProvider.notifier).clear();

      expect(container.read(blockedUsersProvider), isEmpty);
    });
  });

  group('masking', () {
    test('displayNameFor hides only blocked players', () {
      expect(displayNameFor({'rival'}, 'rival', 'Rude Name'), blockedPlayerLabel);
      expect(displayNameFor({'rival'}, 'friend', 'Kai'), 'Kai');
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
