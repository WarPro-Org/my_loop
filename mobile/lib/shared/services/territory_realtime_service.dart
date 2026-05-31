/// Real-time territory update service using SignalR.
///
/// Connects to the backend TerritoryHub and receives hex ownership
/// change events. Clients subscribe to geographic regions (H3 res-3 parent cells)
/// and get notified when territory changes in their visible area.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'package:myloop/shared/services/api_service.dart';

/// Event emitted when hex ownership changes are received from the server.
class HexChangeEvent {
  final String h3Index;
  final double centerLat;
  final double centerLng;
  final String newOwnerId;
  final String newOwnerColor;
  final String newOwnerDisplayName;
  final String? previousOwnerId;

  HexChangeEvent({
    required this.h3Index,
    required this.centerLat,
    required this.centerLng,
    required this.newOwnerId,
    required this.newOwnerColor,
    required this.newOwnerDisplayName,
    this.previousOwnerId,
  });

  factory HexChangeEvent.fromJson(Map<String, dynamic> json) {
    return HexChangeEvent(
      h3Index: json['h3Index'] as String,
      centerLat: (json['centerLat'] as num).toDouble(),
      centerLng: (json['centerLng'] as num).toDouble(),
      newOwnerId: json['newOwnerId'] as String,
      newOwnerColor: json['newOwnerColor'] as String,
      newOwnerDisplayName: json['newOwnerDisplayName'] as String,
      previousOwnerId: json['previousOwnerId'] as String?,
    );
  }
}

/// Service that manages the SignalR connection to the territory hub.
class TerritoryRealtimeService {
  final String _baseUrl;
  HubConnection? _hubConnection;
  final _changeController = StreamController<List<HexChangeEvent>>.broadcast();
  final Set<String> _subscribedRegions = {};
  bool _isConnected = false;

  TerritoryRealtimeService({required String baseUrl}) : _baseUrl = baseUrl;

  /// Stream of hex ownership changes from the server.
  Stream<List<HexChangeEvent>> get onHexChanges => _changeController.stream;

  /// Whether the SignalR connection is active.
  bool get isConnected => _isConnected;

  /// Connect to the SignalR hub.
  Future<void> connect() async {
    if (_hubConnection != null) return;

    final hubUrl = '$_baseUrl/hubs/territory';
    _hubConnection = HubConnectionBuilder()
        .withUrl(hubUrl)
        .withAutomaticReconnect()
        .build();

    _hubConnection!.on('HexOwnershipChanged', _handleHexChanges);

    _hubConnection!.onclose(({error}) {
      _isConnected = false;
    });

    _hubConnection!.onreconnected(({connectionId}) {
      _isConnected = true;
      _resubscribeRegions();
    });

    try {
      await _hubConnection!.start();
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
    }
  }

  /// Subscribe to a geographic region by its H3 res-3 parent cell ID.
  Future<void> joinRegion(String regionId) async {
    if (!_isConnected || _subscribedRegions.contains(regionId)) return;
    _subscribedRegions.add(regionId);
    await _hubConnection?.invoke('JoinRegion', args: [regionId]);
  }

  /// Unsubscribe from a region.
  Future<void> leaveRegion(String regionId) async {
    if (!_isConnected || !_subscribedRegions.contains(regionId)) return;
    _subscribedRegions.remove(regionId);
    await _hubConnection?.invoke('LeaveRegion', args: [regionId]);
  }

  /// Update subscriptions based on visible map bounds.
  /// Call this when the user pans/zooms the map.
  Future<void> updateRegions(Set<String> visibleRegions) async {
    final toLeave = _subscribedRegions.difference(visibleRegions);
    final toJoin = visibleRegions.difference(_subscribedRegions);

    for (final region in toLeave) {
      await leaveRegion(region);
    }
    for (final region in toJoin) {
      await joinRegion(region);
    }
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    _subscribedRegions.clear();
    _isConnected = false;
    await _hubConnection?.stop();
    _hubConnection = null;
  }

  void dispose() {
    disconnect();
    _changeController.close();
  }

  void _handleHexChanges(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    final rawList = arguments[0];
    if (rawList is! List) return;

    final events = rawList
        .whereType<Map<String, dynamic>>()
        .map(HexChangeEvent.fromJson)
        .toList();

    if (events.isNotEmpty) {
      _changeController.add(events);
    }
  }

  Future<void> _resubscribeRegions() async {
    final regions = Set<String>.from(_subscribedRegions);
    _subscribedRegions.clear();
    for (final region in regions) {
      await joinRegion(region);
    }
  }
}

/// Riverpod provider for the territory real-time service.
final territoryRealtimeProvider = Provider<TerritoryRealtimeService>((ref) {
  final service = TerritoryRealtimeService(baseUrl: apiBaseUrl);
  ref.onDispose(() => service.dispose());
  return service;
});
