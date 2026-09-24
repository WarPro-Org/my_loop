/// MyLoop — Mock Walk Simulation: saved-route store (#160)
///
/// Debug-only, file-backed library of named [MockWalkConfig]s plus the
/// last-used config, so a tester can re-run a regression route without
/// re-drawing it. Mirrors the `ProfileCache` file pattern (static service,
/// pure encode/decode, best-effort IO that logs and never throws) with one
/// documented deviation: **no cross-user binding** — entries are tester-authored
/// device-local fixtures containing no server or user data, so there is nothing
/// to leak between accounts and nothing to clear on sign-out. The one field that
/// could hold personal data is `lastUsed.startPoint`, which the designer often
/// fills from a real GPS fix; [MockRouteLibraryNotifier.setLastUsed] refuses to
/// persist a start point near that fix, so the tester's real location never
/// lands in this plaintext (and iCloud-backed) file.
///
/// Writes are serialized through a chained future so interleaved saves can
/// never corrupt the file, and the file on disk always equals the last
/// in-memory library handed to [write]. A corrupt or unreadable file loads as
/// the empty library — the designer degrades to "no saved routes", never a crash.
///
/// Only reachable from the `kDebugMode`-gated designer screen; release builds
/// tree-shake it together with the rest of the simulator.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'mock_walk_config.dart';

final _log = Logger('MockRouteStore');

/// Everything the store persists: the tester's named routes (newest first) and
/// the config of the last walk that was actually started.
class MockRouteLibrary {
  final List<SavedMockRoute> routes;
  final MockWalkConfig? lastUsed;

  const MockRouteLibrary({this.routes = const [], this.lastUsed});

  static const empty = MockRouteLibrary();
}

/// File-backed store for the [MockRouteLibrary]. All methods are static —
/// there is no per-instance state, just JSON in the app documents directory.
class MockRouteStore {
  MockRouteStore._();

  static const _fileName = 'mock_routes.json';

  /// Newest-first cap so a long-lived debug install can't grow the file
  /// unboundedly; saving beyond it drops the oldest route.
  static const int maxSavedRoutes = 20;

  /// A last-used start point within this distance of a real GPS fix counts as
  /// the tester's real location and is not persisted. Wide enough that a start
  /// nudged a little off the fix (map tap, map-centre quick launch) is still
  /// treated as the tester's position.
  static const double deviceFixExclusionMeters = 250.0;

  /// Serializes all pending writes: each new write waits for the previous one,
  /// so two rapid saves can never interleave their file IO.
  static Future<void> _pendingWrite = Future.value();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Pure — unit-testable without touching the filesystem.
  static String encode(MockRouteLibrary library) => jsonEncode({
        'version': 1,
        if (library.lastUsed != null) 'lastUsed': library.lastUsed!.toJson(),
        'routes': [for (final r in library.routes) r.toJson()],
      });

  /// Pure and tolerant: malformed JSON → the empty library; an individually
  /// corrupt route entry is skipped rather than sinking the whole file.
  static MockRouteLibrary decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return MockRouteLibrary.empty;
      final routes = <SavedMockRoute>[];
      final rawRoutes = json['routes'];
      if (rawRoutes is List) {
        for (final entry in rawRoutes) {
          final route = SavedMockRoute.fromJson(entry);
          if (route != null) routes.add(route);
        }
      }
      return MockRouteLibrary(
        routes: routes,
        lastUsed: MockWalkConfig.fromJson(json['lastUsed']),
      );
    } catch (e) {
      _log.warning('Failed to decode saved mock routes — starting empty', e);
      return MockRouteLibrary.empty;
    }
  }

  /// Loads the library, or the empty library if the file is absent/unreadable.
  static Future<MockRouteLibrary> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return MockRouteLibrary.empty;
      return decode(await file.readAsString());
    } catch (e, s) {
      _log.warning('Failed to read saved mock routes', e, s);
      return MockRouteLibrary.empty;
    }
  }

  /// Persists [library] best-effort. Serialized against other writes; the
  /// returned future completes when THIS write has hit the disk (or failed and
  /// been logged).
  static Future<void> write(MockRouteLibrary library) {
    final next = _pendingWrite.then((_) async {
      try {
        final file = await _file();
        await file.writeAsString(encode(library), flush: true);
      } catch (e, s) {
        _log.warning('Failed to write saved mock routes', e, s);
      }
    });
    _pendingWrite = next;
    return next;
  }
}

/// Riverpod front for the designer UI: in-memory library with best-effort
/// write-through. Mutations update state first (the UI reflects the change
/// immediately) and then persist; a failed write only costs durability across
/// restarts, never a crash or a divergent UI.
class MockRouteLibraryNotifier extends AsyncNotifier<MockRouteLibrary> {
  @override
  Future<MockRouteLibrary> build() => MockRouteStore.load();

  /// Waits out the initial disk load if it is still in flight — otherwise the
  /// load completing would overwrite a mutation's state and the next write
  /// would persist the pre-mutation library. A failed load degrades to empty.
  Future<void> _ensureLoaded() async {
    if (state.value != null) return;
    try {
      await future;
    } catch (_) {
      // build() already degrades a failed load to the empty library.
    }
  }

  /// Live state read. Must be called AFTER [_ensureLoaded] and with no await
  /// between this read and the [_replace] write: the read-modify-write has to
  /// be atomic within one event-loop turn or concurrent mutations lose updates.
  MockRouteLibrary get _currentSync => state.value ?? MockRouteLibrary.empty;

  /// Adds (or overwrites, by exact name) a named route, newest first, capped at
  /// [MockRouteStore.maxSavedRoutes].
  Future<void> saveRoute(String name, MockWalkConfig config) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _ensureLoaded();
    final library = _currentSync;
    final kept = [
      SavedMockRoute(name: trimmed, savedAt: DateTime.now(), config: config),
      ...library.routes.where((r) => r.name != trimmed),
    ];
    await _replace(MockRouteLibrary(
      routes: kept.take(MockRouteStore.maxSavedRoutes).toList(),
      lastUsed: library.lastUsed,
    ));
  }

  Future<void> deleteRoute(String name) async {
    await _ensureLoaded();
    final library = _currentSync;
    await _replace(MockRouteLibrary(
      routes: library.routes.where((r) => r.name != name).toList(),
      lastUsed: library.lastUsed,
    ));
  }

  /// Records the config of a walk the tester actually started.
  ///
  /// [deviceFix] is the tester's real position if the designer took a GPS fix.
  /// When the start point lies within [MockRouteStore.deviceFixExclusionMeters]
  /// of it, nothing is recorded: the previous last-used entry (if any) stays,
  /// and on the next open the silent GPS fix supplies the start anyway.
  Future<void> setLastUsed(MockWalkConfig config, {LatLng? deviceFix}) async {
    if (deviceFix != null && _isNear(config.startPoint, deviceFix)) {
      _log.fine('Last-used start is the device location — not persisted');
      return;
    }
    await _ensureLoaded();
    await _replace(MockRouteLibrary(routes: _currentSync.routes, lastUsed: config));
  }

  static bool _isNear(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude) <=
      MockRouteStore.deviceFixExclusionMeters;

  Future<void> _replace(MockRouteLibrary library) async {
    state = AsyncData(library);
    await MockRouteStore.write(library);
  }
}

final mockRouteLibraryProvider =
    AsyncNotifierProvider<MockRouteLibraryNotifier, MockRouteLibrary>(
        MockRouteLibraryNotifier.new);
