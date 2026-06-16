/// Manages loading and state of hex territory cells on the map.
///
/// Handles viewport queries, user-owned hex loading, and state updates.
/// Extracted from _JourneyMapState to keep map widget focused on rendering.
library;

import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/territory_cache.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';
import 'package:myloop/shared/constants/app_constants.dart';

class HexTerritoryManager {
  final ApiService _api;
  final String? _userId;

  List<List<List<double>>> userOwnHexBoundaries = [];
  List<double> userOwnDecayValues = [];
  Map<String, List<List<List<double>>>> otherHexesByColor = {};
  List<TerritoryCell> allCells = [];
  Set<int> userOwnCellIds = {};

  HexTerritoryManager({required ApiService api, required String? userId})
      : _api = api,
        _userId = userId;

  /// Loads ALL hexes owned by this user — no viewport limit.
  ///
  /// On a successful fetch the set is cached to disk; when the backend is
  /// unreachable (offline) we fall back to that cache so the user's own hexes
  /// still render on the Start Journey map instead of vanishing (issue #33).
  Future<void> loadUserOwnHexes() async {
    if (_userId == null) return;
    try {
      final cells = await _api.getUserTerritories(_userId);
      _applyUserOwnCells(cells);
      await TerritoryCache.save(_userId, cells);
    } catch (_) {
      // Offline / fetch failed. Restore the last cached own-hexes, but only if
      // we don't already have fresher data loaded this session (a viewport
      // load may have already populated owned cells).
      if (userOwnCellIds.isEmpty) {
        final cached = await TerritoryCache.load(_userId);
        if (cached != null && cached.isNotEmpty) _applyUserOwnCells(cached);
      }
    }
  }

  /// Replaces the user-owned hex state with [cells] and merges them into the
  /// shared [allCells] cache (newest data wins).
  void _applyUserOwnCells(List<TerritoryCell> cells) {
    userOwnHexBoundaries = cells.map((c) => c.boundary).toList();
    userOwnDecayValues = cells.map((c) => c.decayProgress).toList();
    userOwnCellIds = cells.map((c) => c.cellId).toSet();
    allCells = [
      ...allCells.where((c) => c.ownerId != _userId),
      ...cells,
    ];
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
    // Merge new cells into allCells by cellId (dedup)
    final cellMap = <int, TerritoryCell>{};
    for (final c in allCells) {
      cellMap[c.cellId] = c;
    }
    for (final c in cells) {
      final cell = c as TerritoryCell;
      cellMap[cell.cellId] = cell; // newer data wins
    }

    // Update user-owned tracking from ALL cells (viewport may reveal owned cells)
    final newUserBoundaries = <List<List<double>>>[];
    final newUserDecay = <double>[];
    final newUserCellIds = <int>{};
    final otherByColor = <String, List<List<List<double>>>>{};

    for (final cell in cellMap.values) {
      if (cell.ownerId == _userId) {
        newUserCellIds.add(cell.cellId);
        newUserBoundaries.add(cell.boundary);
        newUserDecay.add(cell.decayProgress);
      } else {
        otherByColor.putIfAbsent(cell.ownerColor, () => []).add(cell.boundary);
      }
    }

    userOwnHexBoundaries = newUserBoundaries;
    userOwnDecayValues = newUserDecay;
    userOwnCellIds = newUserCellIds;
    otherHexesByColor = otherByColor;

    // Evict oldest non-owned cells if cache exceeds limit
    final allList = cellMap.values.toList();
    if (allList.length > AppConstants.maxCachedCells) {
      final ownCells = allList.where((c) => c.ownerId == _userId).toList();
      final otherCells = allList.where((c) => c.ownerId != _userId).toList();
      final keepCount = AppConstants.maxCachedCells - ownCells.length;
      allCells = [...ownCells, ...otherCells.take(keepCount.clamp(0, otherCells.length))];
    } else {
      allCells = allList;
    }
  }

  /// Adds captured hex boundaries to the user's owned list.
  void addCapturedHexes(List<List<List<double>>> boundaries) {
    userOwnHexBoundaries = [...userOwnHexBoundaries, ...boundaries];
  }

  /// Integrates a single step-claimed hex into persistent state.
  /// Removes it from other-players display (if it was stolen) and adds to user-owned.
  void integrateStepClaim(List<List<double>> boundary, int cellId, bool wasStolen) {
    // Remove from other-player display if stolen
    if (wasStolen) {
      final center = _computeCenter(boundary);
      _removeFromOthersByCenter(center[0], center[1]);
    }
    // Add to user's owned hexes (avoid duplicates)
    if (!userOwnCellIds.contains(cellId)) {
      userOwnCellIds.add(cellId);
      userOwnHexBoundaries.add(boundary);
      userOwnDecayValues.add(0.0); // Fresh hex, no decay
    }
  }

  List<double> _computeCenter(List<List<double>> boundary) {
    double latSum = 0, lngSum = 0;
    for (final p in boundary) {
      latSum += p[0];
      lngSum += p[1];
    }
    return [latSum / boundary.length, lngSum / boundary.length];
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

      // If this hex was captured BY us (from another device or real-time confirmation),
      // add to our owned list and remove from others
      if (event.newOwnerId == _userId) {
        // Remove from other-player display (it's ours now)
        _removeFromOthersByCenter(event.centerLat, event.centerLng);
        changed = true;
      } else {
        // Another player captured/stole this hex — remove from all other-player
        // color groups (previous owner) and add to new owner's group
        _removeFromOthersByCenter(event.centerLat, event.centerLng);
        // We don't have full boundary from the event, but we can mark dirty
        // The next viewport reload will show it correctly
        changed = true;
      }

      // Update allCells cache — mark this cell with new owner
      final cellIdx = allCells.indexWhere((c) => c.cellId.toString() == event.h3Index);
      if (cellIdx >= 0) {
        allCells.removeAt(cellIdx);
      }
    }

    return changed;
  }

  /// Remove a hex from otherHexesByColor by matching its center coordinates.
  void _removeFromOthersByCenter(double lat, double lng) {
    for (final entry in otherHexesByColor.entries) {
      entry.value.removeWhere((b) => _boundaryMatchesCenter(b, lat, lng));
    }
    // Remove empty color groups
    otherHexesByColor.removeWhere((_, boundaries) => boundaries.isEmpty);
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

  /// Returns all unique H3 res-3 parent cell IDs from currently loaded cells.
  /// These are the SignalR group keys the client should subscribe to.
  Set<String> getActiveRegionIds() {
    final ids = <String>{};
    for (final cell in allCells) {
      if (cell.parentCellId != 0) {
        ids.add(cell.parentCellId.toString());
      }
    }
    return ids;
  }
}
