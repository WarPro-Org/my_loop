/// Tests for the offline own-hexes cache (issue #33).
///
/// The Start Journey map loads the user's pre-occupied hexes from the backend.
/// Offline that call fails and the map showed none of them. [TerritoryCache]
/// persists the last fetched set so [HexTerritoryManager.loadUserOwnHexes]
/// can restore it when the backend is unreachable.
///
/// Covers:
///   1. [TerritoryCache] codec round-trips cells and enforces the cross-user
///      binding (pure, no filesystem).
///   2. The disk durability invariant: what `save` writes is exactly what
///      `load` reads back (real temp dir, stubbed `path_provider`).
///   3. The fix itself: `loadUserOwnHexes` falls back to the cache when the
///      API throws — the regression that fails without the fallback.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Returns a fixed temp directory for [getApplicationDocumentsPath] so the
/// cache lands on a real, inspectable file during tests.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// An [ApiService] whose territory fetch is fully controlled by the test —
/// either returns a fixed set or throws an offline-style error.
class _FakeApi extends ApiService {
  _FakeApi({required this.result, this.error}) : super(baseUrl: 'http://localhost');

  final List<TerritoryCell> result;
  final Object? error;

  @override
  Future<List<TerritoryCell>> getUserTerritories(String userId) async {
    if (error != null) throw error!;
    return result;
  }
}

TerritoryCell _cell(int id, {String owner = 'user-1', double decay = 0.1}) =>
    TerritoryCell(
      cellId: id,
      ownerId: owner,
      ownerColor: '#00D4AA',
      ownerName: 'Robin',
      boundary: [
        [12.0 + id * 0.001, 56.0],
        [12.0 + id * 0.001, 56.001],
        [12.001 + id * 0.001, 56.001],
      ],
      cooldownExpiresAtUtc: DateTime.utc(2026, 6, 16, 10),
      parentCellId: 99,
      decayProgress: decay,
    );

DioException _offline() => DioException(
      requestOptions: RequestOptions(path: '/api/territories/user/user-1'),
      type: DioExceptionType.connectionError,
    );

/// A reachable server that answered with an error (e.g. HTTP 500) — distinct
/// from being offline.
DioException _serverError() => DioException(
      requestOptions: RequestOptions(path: '/api/territories/user/user-1'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/api/territories/user/user-1'),
        statusCode: 500,
      ),
    );

void main() {
  group('TerritoryCache codec', () {
    test('round-trips cells bound to their user id', () {
      final cells = [_cell(1), _cell(2, decay: 0.7)];
      final restored = TerritoryCache.decode(
        TerritoryCache.encode('user-1', cells),
        'user-1',
      );

      expect(restored, isNotNull);
      expect(restored!.map((c) => c.cellId).toList(), [1, 2]);
      expect(restored[1].decayProgress, 0.7);
      expect(restored[0].boundary, cells[0].boundary);
      expect(restored[0].parentCellId, 99);
    });

    test('returns null when decoded for a different user (cross-user guard)', () {
      // A second account on the same device must never inherit user-1's hexes.
      final raw = TerritoryCache.encode('user-1', [_cell(1)]);
      expect(TerritoryCache.decode(raw, 'user-2'), isNull);
    });

    test('returns null on malformed payload instead of throwing', () {
      expect(TerritoryCache.decode('not json', 'user-1'), isNull);
      expect(TerritoryCache.decode('{}', 'user-1'), isNull);
    });
  });

  group('TerritoryCache disk durability', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('territory_cache_test');
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('what save writes is exactly what load reads back', () async {
      final saved = [_cell(1), _cell(2), _cell(3)];
      await TerritoryCache.save('user-1', saved);

      final loaded = await TerritoryCache.load('user-1');

      // disk == memory: the persisted set matches what was handed to save.
      expect(loaded, isNotNull);
      expect(
        loaded!.map((c) => c.cellId).toSet(),
        saved.map((c) => c.cellId).toSet(),
      );
      // Pin the surviving set so a regression that drops cells can't pass by
      // leaving the file empty.
      expect(loaded.map((c) => c.cellId).toSet(), {1, 2, 3});
    });

    test('load returns null for a different user even on disk', () async {
      await TerritoryCache.save('user-1', [_cell(1)]);
      expect(await TerritoryCache.load('user-2'), isNull);
    });

    test('clear removes the persisted set', () async {
      await TerritoryCache.save('user-1', [_cell(1)]);
      await TerritoryCache.clear();
      expect(await TerritoryCache.load('user-1'), isNull);
    });
  });

  group('HexTerritoryManager offline fallback', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('territory_mgr_test');
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('successful fetch populates owned hexes and writes the cache', () async {
      final cells = [_cell(1), _cell(2)];
      final mgr = HexTerritoryManager(api: _FakeApi(result: cells), userId: 'user-1');

      await mgr.loadUserOwnHexes();

      expect(mgr.userOwnCellIds, {1, 2});
      // The fetch must have persisted the set for a later offline launch.
      final cached = await TerritoryCache.load('user-1');
      expect(cached!.map((c) => c.cellId).toSet(), {1, 2});
    });

    test('offline fetch restores the user\'s own hexes from cache', () async {
      // Seed the cache as a previous online session would have.
      await TerritoryCache.save('user-1', [_cell(1), _cell(2), _cell(3)]);

      final mgr = HexTerritoryManager(
        api: _FakeApi(result: const [], error: _offline()),
        userId: 'user-1',
      );

      await mgr.loadUserOwnHexes();

      // Without the fallback the catch block left this empty and the map showed
      // no owned hexes (issue #33). The fix restores the cached set.
      expect(mgr.userOwnCellIds, {1, 2, 3});
      expect(mgr.userOwnHexBoundaries.length, 3);
    });

    test('reachable server error does NOT fall back to stale cache', () async {
      // Seed the cache as a previous online session would have.
      await TerritoryCache.save('user-1', [_cell(1), _cell(2), _cell(3)]);

      final mgr = HexTerritoryManager(
        api: _FakeApi(result: const [], error: _serverError()),
        userId: 'user-1',
      );

      await mgr.loadUserOwnHexes();

      // A 5xx is a real failure, not offline — masking it with stale cache would
      // be indistinguishable from being offline. Owned hexes must stay empty so
      // the error surfaces (logged) instead of silently showing stale data.
      expect(mgr.userOwnCellIds, isEmpty);
      expect(mgr.userOwnHexBoundaries, isEmpty);
    });

    test('offline with no cache leaves owned hexes empty (no crash)', () async {
      final mgr = HexTerritoryManager(
        api: _FakeApi(result: const [], error: _offline()),
        userId: 'user-1',
      );

      await mgr.loadUserOwnHexes();

      expect(mgr.userOwnCellIds, isEmpty);
    });
  });
}
