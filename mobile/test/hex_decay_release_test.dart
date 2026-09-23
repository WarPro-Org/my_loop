import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/hex_territory_manager.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

/// Regression tests for issue #104 (ML-ERR-007): the decay reaper deleted cells
/// server-side with no SignalR event, so every client kept rendering the released
/// hexes ("ghost territory") until its next viewport poll — and the Home/idle app
/// never polls. The server now broadcasts HexesReleased; the manager must drop the
/// released hexes from every render layer.
void main() {
  const me = 'user-me';
  const rival = 'user-rival';
  const rivalColor = '#FF0000';

  // Distinct boundaries so each cell's derived view entry is identifiable.
  List<List<double>> boundaryAt(double lat, double lng) => [
        [lat, lng],
        [lat + 0.001, lng],
        [lat + 0.001, lng + 0.001],
        [lat, lng + 0.001],
      ];

  TerritoryCell cell(int id, String owner, String color, double lat, double lng) =>
      TerritoryCell(
        cellId: id,
        ownerId: owner,
        ownerColor: color,
        ownerName: owner,
        boundary: boundaryAt(lat, lng),
        parentCellId: 7,
      );

  HexTerritoryManager newManager() =>
      HexTerritoryManager(api: ApiService(), userId: me);

  group('HexTerritoryManager.removeCells', () {
    test('drops a released rival hex from otherHexesByColor and allCells', () {
      final manager = newManager();
      manager.updateFromCells([
        cell(701, rival, rivalColor, 12.900, 77.500),
        cell(702, rival, rivalColor, 12.910, 77.510),
      ]);
      expect(manager.otherHexesByColor[rivalColor], hasLength(2));

      final changed = manager.removeCells(['701']);

      expect(changed, isTrue);
      expect(manager.otherHexesByColor[rivalColor], hasLength(1));
      expect(manager.allCells.map((c) => c.cellId), [702]);
    });

    test('drops a released own hex from the owned layers', () {
      final manager = newManager();
      manager.updateFromCells([
        cell(703, me, '#0000FF', 12.920, 77.520),
        cell(704, me, '#0000FF', 12.930, 77.530),
      ]);
      expect(manager.userOwnCellIds, {703, 704});
      expect(manager.userOwnHexBoundaries, hasLength(2));

      final changed = manager.removeCells(['703']);

      expect(changed, isTrue);
      expect(manager.userOwnCellIds, {704});
      expect(manager.userOwnHexBoundaries, hasLength(1));
      expect(manager.userOwnDecayValues, hasLength(1));
      expect(manager.allCells.map((c) => c.cellId), [704]);
    });

    test('is a no-op for hexes this client never loaded', () {
      final manager = newManager();
      manager.updateFromCells([cell(705, rival, rivalColor, 12.940, 77.540)]);

      final changed = manager.removeCells(['999', 'not-a-number']);

      expect(changed, isFalse);
      expect(manager.otherHexesByColor[rivalColor], hasLength(1));
      expect(manager.allCells, hasLength(1));
    });

    test('deletes the cell from the keyed store so every derived view drops it',
        () {
      final manager = newManager();
      manager.updateFromCells([
        cell(710, me, '#0000FF', 12.960, 77.560),
        cell(711, rival, rivalColor, 12.970, 77.570),
        cell(712, rival, rivalColor, 12.980, 77.580),
      ]);

      final changed = manager.removeCells(['710', '711']);

      expect(changed, isTrue);
      expect(manager.allCells.map((c) => c.cellId), [712]);
      expect(manager.userOwnCellIds, isEmpty);
      expect(manager.otherHexesByColor[rivalColor], hasLength(1));
    });

    test('bumps hexRevision exactly once per release that removed something',
        () {
      final manager = newManager();
      manager.updateFromCells([
        cell(713, rival, rivalColor, 12.990, 77.590),
        cell(714, rival, rivalColor, 13.000, 77.600),
      ]);
      final before = manager.hexRevision.value;

      manager.removeCells(['713', '714']);

      expect(manager.hexRevision.value, before + 1,
          reason: 'the map repaints off hexRevision (#129), not a setState');
    });

    test('a release for cells never loaded does not bump hexRevision or force '
        'a viewport poll', () {
      final manager = newManager();
      manager.updateFromCells([cell(715, rival, rivalColor, 13.010, 77.610)]);
      final before = manager.hexRevision.value;

      manager.removeCells(['999', 'not-a-number']);

      expect(manager.hexRevision.value, before);
      expect(manager.hasUndrawableRealtimeChange, isFalse,
          reason: 'a released cell has nothing left to draw');
    });

    test('removes an empty color group entirely', () {
      final manager = newManager();
      manager.updateFromCells([cell(706, rival, rivalColor, 12.950, 77.550)]);

      manager.removeCells(['706']);

      expect(manager.otherHexesByColor.containsKey(rivalColor), isFalse);
    });
  });

  group('TerritoryRealtimeService HexesReleased freshness', () {
    Map<String, dynamic> payload(List<String> ids) =>
        {'parentCellId': '7', 'h3Indexes': ids};

    test('a release on the current connection marks the hex feed fresh', () {
      final service = TerritoryRealtimeService(baseUrl: 'http://test.local')
        ..debugConnected = true;
      expect(service.timeSinceLastHexEvent, isNull);

      service.debugSimulateHexesReleased([payload(['701'])]);

      expect(service.timeSinceLastHexEvent, isNotNull,
          reason: 'a release is a live region-feed delta, like '
              'HexOwnershipChanged, and feeds the poll back-off (#129)');
    });

    test('an empty release does not mark the feed fresh', () {
      final service = TerritoryRealtimeService(baseUrl: 'http://test.local')
        ..debugConnected = true;

      service.debugSimulateHexesReleased([payload([])]);

      expect(service.timeSinceLastHexEvent, isNull);
    });
  });

  group('HexesReleasedEvent.fromJson', () {
    test('parses the server payload (string ids — H3 ids exceed 2^53)', () {
      final event = HexesReleasedEvent.fromJson({
        'parentCellId': '590112371752960',
        'h3Indexes': ['631196237151909887', '631196237151909888'],
      });

      expect(event.parentCellId, '590112371752960');
      expect(event.h3Indexes, hasLength(2));
      expect(event.h3Indexes.first, '631196237151909887');
    });

    test('tolerates a missing or empty payload', () {
      final event = HexesReleasedEvent.fromJson({});
      expect(event.parentCellId, '');
      expect(event.h3Indexes, isEmpty);
    });
  });
}
