/// Journey screen — live map view for recording territory-capturing walks.
///
/// Displays a full-screen OpenStreetMap with the player's live GPS trail,
/// current position marker, real-time stats (time, distance, GPS points),
/// and start/stop controls. Integrates with [JourneyController] via Riverpod.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/location_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/features/journey/hex_overlay.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';
import 'package:myloop/shared/models/territory_cell.dart';
import 'package:myloop/features/profile/user_profile_screen.dart';
import 'package:myloop/shared/widgets/big_button.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// JOURNEY SCREEN — Full-screen map with overlay controls
/// ─────────────────────────────────────────────────────────────────────────────

/// The main journey recording screen with a layered Stack layout.
///
/// Uses a [Stack] to overlay the map, stats bar (top), and controls (bottom).
/// Watches [journeyControllerProvider] to reactively update the UI as the
/// player walks. Listens for errors and shows them via snackbar.
class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  final _mapKey = GlobalKey<_JourneyMapState>();
  bool _isSubmitting = false;

  /// Handles Stop & Capture — runs from the screen's stable ConsumerState context
  /// so showDialog and ScaffoldMessenger always work correctly.
  Future<void> _onStopCapture() async {
    if (_isSubmitting) return;

    // Read the CURRENT state fresh from the provider (not a stale closure capture)
    final journey = ref.read(journeyControllerProvider);
    final controller = ref.read(journeyControllerProvider.notifier);

    // Capture walk stats before stopJourney() resets the state
    final walkDistance = journey.distanceMeters;
    final walkDuration = journey.elapsed;
    final path = controller.stopJourney();

    if (path.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Walk a bit more to capture territory!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(apiServiceProvider);
      final profile = ref.read(userProfileProvider);
      if (profile.userId == null) return;

      final result = await api.submitClaim(userId: profile.userId!, path: path);
      final capturedCount = (result['cellCount'] as num?)?.toInt() ?? 0;
      final stolenCount = (result['stolenFromOthers'] as num?)?.toInt() ?? 0;

      // Parse boundaries and render captured hexes on map
      final rawBoundaries = result['boundaries'] as List<dynamic>?;
      if (rawBoundaries != null && rawBoundaries.isNotEmpty) {
        final boundaries = rawBoundaries.map<List<List<double>>>((b) =>
          (b as List<dynamic>).map<List<double>>((point) =>
            (point as List<dynamic>).map<double>((v) => (v as num).toDouble()).toList()
          ).toList()
        ).toList();
        _mapKey.currentState?.showCapturedHexes(boundaries);
      }

      // Optimistic hex-count update so the badge reacts instantly
      if (mounted && capturedCount > 0) {
        ref.read(userProfileProvider.notifier).updateStats(
          hexCount: profile.hexCount + capturedCount,
        );
      }

      // Force-reload all hexes from DB as a safety net (covers any edge cases)
      _mapKey.currentState?.forceReloadHexes();

      // Refresh ALL user data from DB: hexCount, streak, distanceKm
      final user = await api.getUser(profile.userId!);

      // Also refresh rank from leaderboard
      int updatedRank = profile.rank;
      try {
        final lb = await api.getLeaderboard(lat: 0, lng: 0, userId: profile.userId!, scope: 'city');
        updatedRank = lb.myRank ?? profile.rank;
      } catch (_) {} // rank stays as-is if leaderboard is unreachable

      if (mounted) {
        ref.read(userProfileProvider.notifier).updateStats(
          hexCount: user.hexCount,
          streak: user.streak,
          distanceKm: user.distanceKm,
          rank: updatedRank,
        );
      }

      // Show celebration using this screen's stable context
      if (mounted) {
        _showCelebration(
          hexCount: capturedCount,
          stolenCount: stolenCount,
          distance: walkDistance,
          duration: walkDuration,
          newStreak: user.streak,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: AppColors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showCelebration({
    required int hexCount,
    required int stolenCount,
    required double distance,
    required Duration duration,
    required int newStreak,
  }) {
    final distanceStr = distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(2)} km'
        : '${distance.toStringAsFixed(0)} m';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final timeStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              const Text(
                'Territory Captured!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              _CelebrationStat(icon: '⬡', label: 'Hexes earned', value: '$hexCount'),
              if (stolenCount > 0)
                _CelebrationStat(icon: '⚔️', label: 'Stolen from others', value: '$stolenCount'),
              _CelebrationStat(icon: '📏', label: 'Distance walked', value: distanceStr),
              _CelebrationStat(icon: '⏱️', label: 'Walk time', value: timeStr),
              _CelebrationStat(icon: '🔥', label: 'Current streak', value: '$newStreak day${newStreak == 1 ? '' : 's'}'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('AWESOME!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journey = ref.watch(journeyControllerProvider);
    final controller = ref.read(journeyControllerProvider.notifier);

    // Listen for error state changes and display as a snackbar
    ref.listen(journeyControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.red,
          ),
        );
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // The map (full screen)
          _JourneyMap(key: _mapKey, journey: journey),

          // Close/back button (top-left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.close, color: AppColors.dark, size: 22),
              ),
            ),
          ),

          // Top bar with stats — vertical left column (below close button)
          if (journey.status == JourneyStatus.tracking)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 0,
              child: _StatsBar(journey: journey),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomControls(
              journey: journey,
              isSubmitting: _isSubmitting,
              onStartJourney: controller.startJourney,
              onStopCapture: _onStopCapture,
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// MAP LAYER
/// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen interactive map that immediately acquires GPS position,
/// follows the user's live location, and auto-updates every 5 seconds.
class _JourneyMap extends ConsumerStatefulWidget {
  final JourneyState journey;
  const _JourneyMap({super.key, required this.journey});

  @override
  ConsumerState<_JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends ConsumerState<_JourneyMap> {
  final MapController _mapController = MapController();
  Position? _initialPosition;
  LatLng? _fallbackCenter; // Used when geolocation fails but hexes exist
  Timer? _locationTimer;
  Timer? _hexRefreshTimer;
  bool _mapReady = false;
  bool _followUser = true; // User can toggle free exploration
  bool _locationError = false;
  double _currentZoom = 17.0;
  bool _useSatellite = true; // Map theme: true=satellite, false=dark
  List<List<List<double>>> _capturedHexBoundaries = [];
  List<List<List<double>>> _myHexBoundaries = [];
  List<List<List<double>>> _otherHexBoundaries = [];
  List<TerritoryCell> _allCells = []; // Keep full cell data for tap detection

  @override
  void initState() {
    super.initState();
    _acquireLocation(); // After GPS resolves → calls _loadAllHexes with wide radius
    // Don't start continuous GPS polling until journey starts — saves battery
    _hexRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshViewportHexes());
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _hexRefreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _acquireLocation() async {
    try {
      final locationService = ref.read(locationServiceProvider);
      await locationService.requestPermission();
      final pos = await locationService.getCurrentPosition();
      if (mounted && pos.latitude.isFinite && pos.longitude.isFinite) {
        setState(() { _initialPosition = pos; _locationError = false; });
        if (_mapReady && _followUser) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 17);
        }
        // Load the user's own hexes (all of them) + nearby hexes from other players
        _loadUserOwnHexes();
        _loadAllHexes();
      } else if (mounted) {
        setState(() => _locationError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _locationError = true);
    }
  }

  /// Loads ALL hexes owned by this user from the server — no viewport limit.
  /// This guarantees the user always sees their territory even if they captured
  /// it elsewhere and just opened the map from a different location.
  Future<void> _loadUserOwnHexes() async {
    final profile = ref.read(userProfileProvider);
    if (profile.userId == null) return;
    try {
      final api = ref.read(apiServiceProvider);
      final cells = await api.getUserTerritories(profile.userId!);
      if (mounted && cells.isNotEmpty) {
        final mine = cells.map((c) => c.boundary).toList();
        // Merge with any already-loaded other-player hexes; re-render immediately
        setState(() {
          _myHexBoundaries = mine;
          _allCells = [..._allCells.where((c) => c.ownerId != profile.userId), ...cells];
        });
        // If map is ready, fly to user's hexes center so they can see them
        if (_mapReady && cells.isNotEmpty) {
          final first = cells.first.boundary.first;
          _mapController.move(LatLng(first[0], first[1]), _mapController.camera.zoom);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadViewportHexes(double lat, double lng) async {
    try {
      final api = ref.read(apiServiceProvider);
      final offset = 0.02; // ~2.2km radius
      final cells = await api.getTerritories(
        minLat: lat - offset,
        minLng: lng - offset,
        maxLat: lat + offset,
        maxLng: lng + offset,
      );
      _updateHexState(cells);
    } catch (_) {}
  }

  /// Loads hexes in a wide area around the user's known position.
  /// Called by _acquireLocation after GPS resolves successfully.
  Future<void> _loadAllHexes() async {
    if (_initialPosition == null) return;
    try {
      final api = ref.read(apiServiceProvider);
      final lat = _initialPosition!.latitude;
      final lng = _initialPosition!.longitude;
      final offset = 0.05; // ~5.5km radius — wider than viewport to preload nearby hexes
      final cells = await api.getTerritories(
        minLat: lat - offset,
        minLng: lng - offset,
        maxLat: lat + offset,
        maxLng: lng + offset,
      );
      _updateHexState(cells);
    } catch (_) {}
  }

  /// Refreshes hexes based on current viewport bounds.
  Future<void> _refreshViewportHexes() async {
    if (!_mapReady) return;
    final bounds = _mapController.camera.visibleBounds;
    try {
      final api = ref.read(apiServiceProvider);
      final cells = await api.getTerritories(
        minLat: bounds.south,
        minLng: bounds.west,
        maxLat: bounds.north,
        maxLng: bounds.east,
      );
      _updateHexState(cells);
    } catch (_) {}
  }

  /// Splits cells into user's own hexes and others (single uniform color).
  void _updateHexState(List<dynamic> cells) {
    final profile = ref.read(userProfileProvider);
    final mine = <List<List<double>>>[];
    final otherBounds = <List<List<double>>>[];
    final allCells = <TerritoryCell>[];

    for (final c in cells) {
      final cell = c as TerritoryCell;
      allCells.add(cell);
      if (cell.ownerId == profile.userId) {
        mine.add(cell.boundary);
      } else {
        otherBounds.add(cell.boundary);
      }
    }

    if (mounted) {
      setState(() {
        _myHexBoundaries = mine;
        _otherHexBoundaries = otherBounds;
        _allCells = allCells;
      });
    }
  }

  /// Handles map tap — checks if user tapped inside a hex polygon.
  void _onMapTap(LatLng latLng) {
    final tappedCell = _findTappedCell(latLng.latitude, latLng.longitude);
    if (tappedCell != null) {
      _showHexOwnerSheet(tappedCell);
    }
  }

  /// Point-in-polygon test to find which cell was tapped.
  TerritoryCell? _findTappedCell(double lat, double lng) {
    for (final cell in _allCells) {
      if (_pointInPolygon(lat, lng, cell.boundary)) {
        return cell;
      }
    }
    return null;
  }

  /// Ray-casting point-in-polygon algorithm.
  bool _pointInPolygon(double lat, double lng, List<List<double>> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final yi = polygon[i][0], xi = polygon[i][1];
      final yj = polygon[j][0], xj = polygon[j][1];
      if (((yi > lat) != (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Shows a bottom sheet with hex owner info and link to their profile.
  void _showHexOwnerSheet(TerritoryCell cell) {
    final profile = ref.read(userProfileProvider);
    final isOwn = cell.ownerId == profile.userId;
    final ownerColor = Color(int.parse(cell.ownerColor.replaceFirst('#', ''), radix: 16) | 0xFF000000);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: ownerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ownerColor, width: 2),
                  ),
                  child: const Icon(Icons.hexagon, size: 28, color: Colors.white70),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOwn ? 'Your Hex' : '${cell.ownerName}\'s Hex',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      Text(
                        isOwn ? 'You own this territory' : 'Owned by ${cell.ownerName}',
                        style: TextStyle(color: AppColors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isOwn) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        userId: cell.ownerId,
                        name: cell.ownerName,
                        avatarId: 0,
                        color: cell.ownerColor,
                        rank: 0,
                      ),
                    ));
                  },
                  icon: const Icon(Icons.person, size: 18),
                  label: Text('View ${cell.ownerName}\'s Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refreshPosition() async {
    final journey = ref.read(journeyControllerProvider);
    if (journey.status == JourneyStatus.tracking) return;
    try {
      final locationService = ref.read(locationServiceProvider);
      final pos = await locationService.getCurrentPosition();
      if (mounted && pos.latitude.isFinite && pos.longitude.isFinite) {
        setState(() => _initialPosition = pos);
        // Only move if following
        if (_mapReady && _followUser) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
        }
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _JourneyMap old) {
    super.didUpdateWidget(old);
    // Start/stop location polling based on tracking state
    if (widget.journey.status == JourneyStatus.tracking && _locationTimer == null) {
      _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPosition());
    } else if (widget.journey.status != JourneyStatus.tracking && _locationTimer != null) {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
    // Only follow during tracking if followUser is enabled
    final pos = widget.journey.currentPosition;
    if (pos != null && _mapReady && _followUser && pos.latitude.isFinite && pos.longitude.isFinite) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
    }
  }

  /// Called after claim submission — renders captured hexes on map
  void showCapturedHexes(List<List<List<double>>> boundaries) {
    setState(() {
      _capturedHexBoundaries = boundaries;
      // Immediately add to user's hex polygon boundaries for rendering
      _myHexBoundaries = [..._myHexBoundaries, ...boundaries];
    });
  }

  /// Forces an immediate refresh of territory hexes from the server.
  /// Called after claim submission so newly captured hexes appear without
  /// waiting for the periodic 30-second timer.
  void forceReloadHexes() {
    _loadUserOwnHexes(); // Always reload user's full territory first
    if (_mapReady) {
      _refreshViewportHexes(); // Also refresh viewport for nearby players
    } else if (_initialPosition != null) {
      _loadViewportHexes(_initialPosition!.latitude, _initialPosition!.longitude);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final profile = ref.watch(userProfileProvider);
    final userColor = Color(int.parse(profile.color.replaceFirst('#', ''), radix: 16) | 0xFF000000);

    // Show loading spinner while acquiring location (unless we have a fallback)
    if (_initialPosition == null && _fallbackCenter == null && journey.currentPosition == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_locationError) ...[
              const Icon(Icons.location_off, size: 48, color: AppColors.grey),
              const SizedBox(height: 12),
              const Text('Could not get your location', style: TextStyle(color: AppColors.grey)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () { setState(() => _locationError = false); _acquireLocation(); },
                child: const Text('Retry'),
              ),
            ] else ...[
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              const Text('Getting your location...', style: TextStyle(color: AppColors.grey)),
            ],
          ],
        ),
      );
    }

    LatLng center;
    if (journey.currentPosition != null) {
      center = LatLng(journey.currentPosition!.latitude, journey.currentPosition!.longitude);
    } else if (_initialPosition != null) {
      center = LatLng(_initialPosition!.latitude, _initialPosition!.longitude);
    } else {
      center = _fallbackCenter!;
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 17,
            onMapReady: () {
              _mapReady = true;
              if (_initialPosition != null) {
                _mapController.move(LatLng(_initialPosition!.latitude, _initialPosition!.longitude), 17);
              } else if (_fallbackCenter != null) {
                _mapController.move(_fallbackCenter!, 17);
              }
            },
            onPositionChanged: (pos, hasGesture) {
              // Track zoom for adaptive hex rendering
              if (pos.zoom != _currentZoom) {
                setState(() => _currentZoom = pos.zoom);
              }
              // User panned manually — disable auto-follow
              if (hasGesture && _followUser) {
                setState(() => _followUser = false);
              }
            },
            onTap: (tapPos, latLng) => _onMapTap(latLng),
          ),
          children: [
            TileLayer(
              urlTemplate: _useSatellite
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
              subdomains: _useSatellite ? const [] : const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.myloop.app',
            ),

            // Labels overlay — place names, roads, boundaries on top of satellite
            if (_useSatellite)
              TileLayer(
                urlTemplate: 'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.myloop.app',
              ),

            // Other players' hex polygons (black, full animation)
            if (_otherHexBoundaries.isNotEmpty)
              AnimatedHexOverlay(
                hexBoundaries: _otherHexBoundaries,
                userColor: const Color(0xFF1A1A2E), // near-black for others
                currentZoom: _currentZoom,
                isNewCapture: false,
              ),

            // User's owned hex polygons (animated overlay with glow)
            if (_myHexBoundaries.isNotEmpty)
              AnimatedHexOverlay(
                hexBoundaries: _myHexBoundaries,
                userColor: userColor,
                currentZoom: _currentZoom,
              ),

            // Captured hex polygons (from current session — extra glow)
            if (_capturedHexBoundaries.isNotEmpty)
              AnimatedHexOverlay(
                hexBoundaries: _capturedHexBoundaries,
                userColor: userColor,
                currentZoom: _currentZoom,
                isNewCapture: true,
              ),

            // Draw the walked path
            if (journey.path.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: journey.path.map((p) => LatLng(p[0], p[1])).toList(),
                    color: AppColors.primary,
                    strokeWidth: 4,
                  ),
                ],
              ),

            // User position marker with avatar
            if (journey.currentPosition != null || _initialPosition != null || _fallbackCenter != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: journey.currentPosition != null
                        ? LatLng(journey.currentPosition!.latitude, journey.currentPosition!.longitude)
                        : _initialPosition != null
                            ? LatLng(_initialPosition!.latitude, _initialPosition!.longitude)
                            : _fallbackCenter!,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: userColor.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: AvatarWidget(
                          avatarId: profile.avatarId,
                          color: profile.color,
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Re-center button (shown when user has panned away)
        if (!_followUser)
          Positioned(
            bottom: 140,
            right: 16,
            child: GestureDetector(
              onTap: () {
                setState(() => _followUser = true);
                final trackPos = widget.journey.currentPosition;
                final pos = trackPos ?? _initialPosition;
                if (pos != null && _mapReady) {
                  _mapController.move(
                    LatLng(pos.latitude, pos.longitude),
                    _mapController.camera.zoom,
                  );
                }
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: const Icon(Icons.my_location, color: AppColors.primary, size: 24),
              ),
            ),
          ),

        // Map theme toggle button (top-right)
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: GestureDetector(
            onTap: () => setState(() => _useSatellite = !_useSatellite),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Icon(
                _useSatellite ? Icons.dark_mode : Icons.satellite_alt,
                color: AppColors.dark,
                size: 20,
              ),
            ),
          ),
        ),

        // Hex count badge (top-right, below theme toggle)
        Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hexagon, color: userColor, size: 18),
                const SizedBox(width: 4),
                Text(
                  '${profile.hexCount}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.dark),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// STATS OVERLAY
/// ─────────────────────────────────────────────────────────────────────────────

/// Floating stats bar shown at the top during active tracking.
///
/// Displays elapsed time (MM:SS), distance walked (m or km), and the
/// number of GPS points recorded so far.
class _StatsBar extends StatelessWidget {
  final JourneyState journey;
  const _StatsBar({required this.journey});

  @override
  Widget build(BuildContext context) {
    final minutes = journey.elapsed.inMinutes;
    final seconds = journey.elapsed.inSeconds % 60;
    final distanceKm = journey.distanceMeters / 1000;

    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(24),
          1: IntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          _buildStatRow(Icons.schedule_rounded, const Color(0xFF00D4AA),
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'),
          _buildSpacerRow(),
          _buildStatRow(Icons.route_rounded, const Color(0xFF6C5CE7),
            distanceKm >= 1 ? '${distanceKm.toStringAsFixed(2)} km' : '${journey.distanceMeters.toInt()} m'),
          _buildSpacerRow(),
          _buildStatRow(Icons.hexagon_rounded, const Color(0xFFF59E0B), '—'),
        ],
      ),
    );
  }

  TableRow _buildStatRow(IconData icon, Color color, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(child: Icon(icon, size: 18, color: color)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6),
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  TableRow _buildSpacerRow() {
    return TableRow(
      children: [
        const SizedBox(height: 1),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// BOTTOM CONTROLS
/// ─────────────────────────────────────────────────────────────────────────────

/// Bottom panel with Start/Stop buttons depending on journey state.
///
/// Stateless — all async claim logic lives in _JourneyScreenState._onStopCapture.
class _BottomControls extends StatelessWidget {
  final JourneyState journey;
  final bool isSubmitting;
  final VoidCallback onStartJourney;
  final VoidCallback onStopCapture;
  const _BottomControls({
    required this.journey,
    required this.isSubmitting,
    required this.onStartJourney,
    required this.onStopCapture,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: journey.status == JourneyStatus.tracking
            ? _buildTrackingControls()
            : _buildIdleControls(),
      ),
    );
  }

  Widget _buildIdleControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '🚶 Ready to capture territory?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Walk a loop to claim hexagons!',
          style: TextStyle(fontSize: 13, color: AppColors.grey),
        ),
        const SizedBox(height: 16),
        BigButton(
          label: 'START JOURNEY',
          icon: Icons.play_arrow,
          onPressed: onStartJourney,
        ),
      ],
    );
  }

  Widget _buildTrackingControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '🔴 Recording your path...',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Walk back to your start to close the loop!',
          style: TextStyle(fontSize: 13, color: AppColors.grey),
        ),
        const SizedBox(height: 16),
        BigButton(
          label: isSubmitting ? 'SUBMITTING...' : 'STOP & CAPTURE',
          icon: isSubmitting ? Icons.hourglass_empty : Icons.stop,
          color: AppColors.red,
          onPressed: isSubmitting ? null : onStopCapture,
        ),
      ],
    );
  }
}


class _CelebrationStat extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  const _CelebrationStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15, color: Colors.grey)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
