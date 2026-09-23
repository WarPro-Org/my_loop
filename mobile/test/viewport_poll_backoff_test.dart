/// Regression tests for the #129 viewport-poll back-off.
///
/// The first version skipped the Journey map's 30s poll whenever ANY hex
/// delta had arrived in the last 60s — from any region, including the user's
/// own step claims echoed back by the hub. But that poll is the only thing
/// that loads the viewport after a pan/zoom and the only way to draw a hex
/// the client never loaded, so while the user walked (or anyone nearby
/// played) panned-into areas stayed empty and other players' captures of
/// unowned hexes never appeared.
///
/// These tests drive [ViewportPollBackoff] — the exact object
/// `_JourneyMapState._pollViewportHexesIfStale` consults — with a real
/// [TerritoryRealtimeService] and [HexTerritoryManager].
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/features/journey/viewport_poll_backoff.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

const _knownCellId = 101;
const _unknownCellId = 202;
const _region = '5';

/// Joins regions without a live hub.
class _JoinableRealtime extends TerritoryRealtimeService {
  _JoinableRealtime() : super(baseUrl: 'http://test.local');

  @override
  Future<void> invokeJoinRegion(String regionId) async {}
}

/// Serves one fixed viewport response so [HexTerritoryManager.loadViewport]
/// runs for real.
class _ViewportApi extends ApiService {
  bool fail = false;

  @override
  Future<List<TerritoryCell>> getTerritories({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    if (fail) throw Exception('simulated viewport load failure');
    return [_cell(_knownCellId)];
  }
}

TerritoryCell _cell(int id, {int parentCellId = 0}) => TerritoryCell(
      cellId: id,
      ownerId: 'other-user',
      ownerColor: '#FF0000',
      parentCellId: parentCellId,
      boundary: const [
        [1.0, 1.0],
        [1.0, 1.001],
        [1.001, 1.001],
      ],
    );

Map<String, dynamic> _eventJson(int cellId) => {
      'h3Index': '$cellId',
      'centerLat': 1.0,
      'centerLng': 1.0,
      'newOwnerId': 'someone',
      'newOwnerColor': '#00FF00',
      'newOwnerDisplayName': 'Someone',
    };

/// The hub payload shape `HexOwnershipChanged` delivers.
List<Object?> _hexPayload(int cellId) => [
      [_eventJson(cellId)],
    ];

HexChangeEvent _event(int cellId) => HexChangeEvent.fromJson(_eventJson(cellId));

final _polledBounds = LatLngBounds(const LatLng(1, 1), const LatLng(2, 2));
final _insidePolled =
    LatLngBounds(const LatLng(1.2, 1.2), const LatLng(1.8, 1.8));
final _pannedAway =
    LatLngBounds(const LatLng(1.5, 1.5), const LatLng(2.5, 2.5));

void main() {
  late Duration now;
  late ViewportPollBackoff backoff;
  late _JoinableRealtime realtime;
  late _ViewportApi api;
  late HexTerritoryManager hexes;

  /// Performs a successful viewport load exactly as the screen does:
  /// load, then record the bounds only when it succeeded.
  Future<void> pollSucceeds(LatLngBounds bounds) async {
    final loaded = await hexes.loadViewport(
      minLat: bounds.south, minLng: bounds.west,
      maxLat: bounds.north, maxLng: bounds.east,
    );
    if (loaded) backoff.recordSuccessfulPoll(bounds);
  }

  bool skips(LatLngBounds viewport) => backoff.shouldSkipTick(
        viewport: viewport,
        realtime: realtime,
        hexes: hexes,
      );

  setUp(() async {
    now = Duration.zero;
    backoff = ViewportPollBackoff(clock: () => now);
    realtime = _JoinableRealtime()..debugConnected = true;
    api = _ViewportApi();
    hexes = HexTerritoryManager(api: api, userId: 'me');
    await pollSucceeds(_polledBounds);
  });

  test('(c) unchanged viewport + fresh delta for a drawable cell → skip', () {
    realtime.debugSimulateHexChanges(_hexPayload(_knownCellId));
    hexes.applyRealtimeChanges([_event(_knownCellId)]);

    expect(skips(_insidePolled), isTrue);
  });

  test('(a) fresh delta but viewport moved outside the last polled bounds → poll',
      () {
    realtime.debugSimulateHexChanges(_hexPayload(_knownCellId));

    expect(skips(_pannedAway), isFalse,
        reason: 'the poll is the only thing that loads a panned-into area');
  });

  test('(b) delta for a hex with no known boundary forces the next poll', () async {
    realtime.debugSimulateHexChanges(_hexPayload(_unknownCellId));
    hexes.applyRealtimeChanges([_event(_unknownCellId)]);

    expect(skips(_insidePolled), isFalse,
        reason: 'only a viewport load can draw a cell the client never saw');

    // A successful load clears it again.
    await pollSucceeds(_polledBounds);
    realtime.debugSimulateHexChanges(_hexPayload(_knownCellId));
    expect(skips(_insidePolled), isTrue);
  });

  test('a failed load keeps the pending undrawable change and the old bounds',
      () async {
    hexes.applyRealtimeChanges([_event(_unknownCellId)]);
    api.fail = true;
    await pollSucceeds(_pannedAway);
    realtime.debugSimulateHexChanges(_hexPayload(_knownCellId));

    expect(hexes.hasUndrawableRealtimeChange, isTrue);
    expect(skips(_pannedAway), isFalse,
        reason: 'failed bounds must never be treated as polled');
  });

  test('no delta yet on this connection → poll', () {
    expect(skips(_insidePolled), isFalse);
  });

  test('delta received before a reconnect → poll', () {
    realtime.debugSimulateHexChanges(_hexPayload(_knownCellId));
    realtime.debugSimulateReconnecting();
    realtime.debugConnected = true;
    expect(skips(_insidePolled), isFalse);
  });

  test('loaded cell in a region without a confirmed join → poll', () async {
    hexes.updateFromCells([_cell(_knownCellId, parentCellId: int.parse(_region))]);
    realtime.debugSimulateHexChanges(_hexPayload(_knownCellId));
    expect(skips(_insidePolled), isFalse);

    await realtime.joinRegion(_region);
    expect(skips(_insidePolled), isTrue);
  });

  test('never skips past the max back-off since the last successful poll', () {
    realtime.debugSimulateHexChanges(_hexPayload(_knownCellId));
    now = const Duration(seconds: AppConstants.viewportPollMaxBackoffSeconds);
    expect(skips(_insidePolled), isFalse,
        reason: 'deltas carry no cooldown; bound how long it can lag');
  });
}
