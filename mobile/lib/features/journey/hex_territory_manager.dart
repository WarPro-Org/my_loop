/// Manages loading and state of hex territory cells on the map.
///
/// Handles viewport queries, user-owned hex loading, and state updates.
/// Extracted from _JourneyMapState to keep map widget focused on rendering.
library;

import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/constants/app_constants.dart';

class HexTerritoryManager {
  final ApiService _api;
  final String? _userId;

  List<List<List<double>>> userOwnHexBoundaries = [];
  Map<String, List<List<List<double>>>> otherHexesByColor = {};
  List<TerritoryCell> allCells = [];
  Set<int> userOwnCellIds = {};

  HexTerritoryManager({required ApiService api, required String? userId})
      : _api = api,
        _userId = userId;

  /// Loads ALL hexes owned by this user — no viewport limit.
  Future<void> loadUserOwnHexes() async {
    if (_userId == null) return;
    try {
      final cells = await _api.getUserTerritories(_userId);
      userOwnHexBoundaries = cells.map((c) => c.boundary).toList();
      userOwnCellIds = cells.map((c) => c.cellId).toSet();
      allCells = [
        ...allCells.where((c) => c.ownerId != _userId),
        ...cells,
      ];
    } catch (_) {}
  }

  /// Loads hexes in a wide area around [lat], [lng].
  Future<void> loadWideArea(double lat, double lng) async {
    try {
      const offset = AppConstants.wideViewportOffset;
      final cells = await _api.getTerritories(
        minLat: lat - offset,
        minLng: lng - offset,
        maxLat: lat + offset,
        maxLng: lng + offset,
      );
      updateFromCells(cells);
    } catch (_) {}
  }

  /// Loads hexes within a viewport bounding box.
  Future<void> loadViewport({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    try {
      final cells = await _api.getTerritories(
        minLat: minLat,
        minLng: minLng,
        maxLat: maxLat,
        maxLng: maxLng,
      );
      updateFromCells(cells);
    } catch (_) {}
  }

  /// Splits cells into user-owned and others (grouped by owner color).
  void updateFromCells(List<dynamic> cells) {
    final otherByColor = <String, List<List<List<double>>>>{};
    final updatedCells = <TerritoryCell>[...allCells.where((c) => c.ownerId == _userId)];

    for (final c in cells) {
      final cell = c as TerritoryCell;
      if (cell.ownerId == _userId) {
        if (!userOwnCellIds.contains(cell.cellId)) {
          updatedCells.add(cell);
        }
      } else {
        otherByColor.putIfAbsent(cell.ownerColor, () => []).add(cell.boundary);
        updatedCells.add(cell);
      }
    }

    otherHexesByColor = otherByColor;

    // Evict oldest non-owned cells if cache exceeds limit
    if (updatedCells.length > AppConstants.maxCachedCells) {
      final ownCells = updatedCells.where((c) => c.ownerId == _userId).toList();
      final otherCells = updatedCells.where((c) => c.ownerId != _userId).toList();
      final keepCount = AppConstants.maxCachedCells - ownCells.length;
      allCells = [...ownCells, ...otherCells.take(keepCount.clamp(0, otherCells.length))];
    } else {
      allCells = updatedCells;
    }
  }

  /// Adds captured hex boundaries to the user's owned list.
  void addCapturedHexes(List<List<List<double>>> boundaries) {
    userOwnHexBoundaries = [...userOwnHexBoundaries, ...boundaries];
  }

  /// Applies real-time hex ownership changes from SignalR.
  /// Returns true if any visible change occurred (caller should rebuild map).
  bool applyRealtimeChanges(List<HexChangeEvent> events) {
    if (events.isEmpty) return false;

    bool changed = false;
    for (final event in events) {
      // If this hex was stolen FROM us, remove from our owned list
      if (event.previousOwnerId == _userId) {
        userOwnCellIds.removeWhere((id) => id.toString() == event.h3Index);
        userOwnHexBoundaries.removeWhere((b) => _boundaryMatchesCenter(b, event.centerLat, event.centerLng));
        changed = true;
      }

      // If this hex was captured BY us (from another device or real-time confirmation)
      if (event.newOwnerId == _userId) {
        changed = true;
      }

      // Update the other-players color map
      otherHexesByColor.putIfAbsent(event.newOwnerColor, () => []);
      changed = true;
    }

    return changed;
  }

  bool _boundaryMatchesCenter(List<List<double>> boundary, double lat, double lng) {
    if (boundary.isEmpty) return false;
    double avgLat = 0, avgLng = 0;
    for (final p in boundary) {
      avgLat += p[0];
      avgLng += p[1];
    }
    avgLat /= boundary.length;
    avgLng /= boundary.length;
    return (avgLat - lat).abs() < 0.0001 && (avgLng - lng).abs() < 0.0001;
  }
}
