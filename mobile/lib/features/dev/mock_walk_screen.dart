/// MyLoop — Mock Walk Simulation: dev control screen (#29)
///
/// Debug-only screen letting a tester configure and launch a simulated walk from
/// their desk: pick a route shape, tap a start point / waypoints on the map, set
/// walking speed and jitter, then start. Reachable only via the debug-only route
/// `/dev/mock-walk` (registered under `kDebugMode`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:myloop/shared/services/mock/mock_walk_config.dart';
import 'package:myloop/shared/services/mock/mock_walk_engine.dart';

/// User-facing copy + map presentation values for the dev screen, kept out of the
/// widget tree (CLAUDE.md: "No hardcoded strings — use constants").
class _Strings {
  _Strings._();
  static const title = 'Mock Walk (debug)';
  static const clearWaypoints = 'Clear waypoints';
  static const start = 'START MOCK WALK';
  static const routeLoop = 'Loop';
  static const routeStraight = 'Straight';
  static const routeWaypoints = 'Waypoints';
  static const mockModeTitle = 'Mock mode (uses simulated GPS)';
  static const mockModeSubtitle = 'Off = real GPS. START below turns this on.';
  static const jitterTitle = 'GPS jitter (required to pass anti-cheat)';
  static const jitterWarning =
      'Warning: with jitter off, straight/loop routes are rejected by the '
      'server smoothness check (bearing std-dev < 2°).';
  static const needTwoWaypoints = 'Add at least 2 waypoints for a multi-waypoint route.';
  static String tapHintWaypoints(int count) =>
      'Tap the map to add waypoints (in order). $count set.';
  static const tapHintStart = 'Tap the map to set the start point.';
  static String speed(double v) => 'Speed: ${v.toStringAsFixed(1)} m/s';
  static String loopRadius(double v) => 'Loop radius: ${v.toStringAsFixed(0)} m';
  static String length(double v) => 'Length: ${v.toStringAsFixed(0)} m';
}

class MockWalkScreen extends ConsumerStatefulWidget {
  const MockWalkScreen({super.key});

  @override
  ConsumerState<MockWalkScreen> createState() => _MockWalkScreenState();
}

class _MockWalkScreenState extends ConsumerState<MockWalkScreen> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(mockWalkConfigProvider);
    final anchors = _previewAnchors(config);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_Strings.title),
        actions: [
          IconButton(
            tooltip: _Strings.clearWaypoints,
            icon: const Icon(Icons.layers_clear),
            onPressed: () => _set(config.copyWith(waypoints: const [])),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMap(config, anchors)),
          _buildControls(config),
        ],
      ),
    );
  }

  // ── Map ─────────────────────────────────────────────────────────────────────

  Widget _buildMap(MockWalkConfig config, List<LatLng> anchors) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: config.startPoint,
        initialZoom: 16,
        onTap: (_, latLng) => _onMapTap(config, latLng),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.myloop.app',
          maxNativeZoom: 19,
        ),
        if (anchors.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: anchors, strokeWidth: 3, color: Colors.cyanAccent),
            ],
          ),
        MarkerLayer(markers: _markers(config)),
      ],
    );
  }

  List<Marker> _markers(MockWalkConfig config) {
    final markers = <Marker>[
      Marker(
        point: config.startPoint,
        width: 28,
        height: 28,
        child: const Icon(Icons.my_location, color: Colors.greenAccent, size: 28),
      ),
    ];
    for (final wp in config.waypoints) {
      markers.add(Marker(
        point: wp,
        width: 20,
        height: 20,
        child: const Icon(Icons.circle, color: Colors.orangeAccent, size: 14),
      ));
    }
    return markers;
  }

  void _onMapTap(MockWalkConfig config, LatLng latLng) {
    if (config.routeType == MockRouteType.multiWaypoint) {
      _set(config.copyWith(waypoints: [...config.waypoints, latLng]));
    } else {
      _set(config.copyWith(startPoint: latLng));
    }
  }

  // ── Controls ────────────────────────────────────────────────────────────────

  Widget _buildControls(MockWalkConfig config) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(_Strings.mockModeTitle),
            subtitle: const Text(_Strings.mockModeSubtitle),
            value: config.enabled,
            onChanged: (v) => _set(config.copyWith(enabled: v)),
          ),
          _tapHint(config),
          const SizedBox(height: 8),
          SegmentedButton<MockRouteType>(
            segments: const [
              ButtonSegment(value: MockRouteType.loop, label: Text(_Strings.routeLoop)),
              ButtonSegment(value: MockRouteType.straight, label: Text(_Strings.routeStraight)),
              ButtonSegment(value: MockRouteType.multiWaypoint, label: Text(_Strings.routeWaypoints)),
            ],
            selected: {config.routeType},
            onSelectionChanged: (s) => _set(config.copyWith(routeType: s.first)),
          ),
          const SizedBox(height: 12),
          _slider(
            label: _Strings.speed(config.speedMps),
            value: config.speedMps,
            min: MockWalkConstants.minSpeedMps,
            max: MockWalkConstants.maxSpeedMps,
            onChanged: (v) => _set(config.copyWith(speedMps: v)),
          ),
          if (config.routeType == MockRouteType.loop)
            _slider(
              label: _Strings.loopRadius(config.loopRadiusMeters),
              value: config.loopRadiusMeters,
              min: MockWalkConstants.minLoopRadiusMeters,
              max: MockWalkConstants.maxLoopRadiusMeters,
              onChanged: (v) => _set(config.copyWith(loopRadiusMeters: v)),
            ),
          if (config.routeType == MockRouteType.straight)
            _slider(
              label: _Strings.length(config.straightLengthMeters),
              value: config.straightLengthMeters,
              min: MockWalkConstants.minStraightLengthMeters,
              max: MockWalkConstants.maxStraightLengthMeters,
              onChanged: (v) => _set(config.copyWith(straightLengthMeters: v)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(_Strings.jitterTitle),
            value: config.jitterEnabled,
            onChanged: (v) => _set(config.copyWith(jitterEnabled: v)),
          ),
          if (!config.jitterEnabled)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                _Strings.jitterWarning,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.directions_walk),
              label: const Text(_Strings.start),
              onPressed: () => _startWalk(config),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tapHint(MockWalkConfig config) {
    final text = config.routeType == MockRouteType.multiWaypoint
        ? _Strings.tapHintWaypoints(config.waypoints.length)
        : _Strings.tapHintStart;
    return Text(text, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic));
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _set(MockWalkConfig config) => ref.read(mockWalkConfigProvider.notifier).update(config);

  void _startWalk(MockWalkConfig config) {
    if (config.routeType == MockRouteType.multiWaypoint && config.waypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_Strings.needTwoWaypoints)),
      );
      return;
    }
    // Enable the mock (swaps locationServiceProvider) and launch the normal journey.
    ref.read(mockWalkConfigProvider.notifier).update(config.copyWith(enabled: true));
    context.go('/journey');
  }

  /// Route geometry preview (no jitter) so the tester sees the shape they'll walk.
  List<LatLng> _previewAnchors(MockWalkConfig config) {
    return MockWalkEngine(config.copyWith(jitterEnabled: false)).buildRouteAnchors();
  }
}
