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

          // Top bar with stats
          if (journey.status == JourneyStatus.tracking)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _StatsBar(journey: journey),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomControls(
              journey: journey,
              controller: controller,
              mapKey: _mapKey,
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
  bool _mapReady = false;
  bool _followUser = true; // User can toggle free exploration
  bool _locationError = false;
  double _currentZoom = 17.0;
  List<List<List<double>>> _capturedHexBoundaries = [];
  List<List<List<double>>> _ownedHexBoundaries = [];

  @override
  void initState() {
    super.initState();
    _acquireLocation();
    _loadAllOwnedHexes(); // Also load hexes independent of geolocation
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPosition());
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
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
        // Load owned hexes near this position
        _loadOwnedHexes(pos.latitude, pos.longitude);
      } else if (mounted) {
        setState(() => _locationError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _locationError = true);
    }
  }

  Future<void> _loadOwnedHexes(double lat, double lng) async {
    try {
      final api = ref.read(apiServiceProvider);
      // Load hexes in ~2km radius around user
      final offset = 0.02; // ~2.2km
      final cells = await api.getTerritories(
        minLat: lat - offset,
        minLng: lng - offset,
        maxLat: lat + offset,
        maxLng: lng + offset,
      );
      final profile = ref.read(userProfileProvider);
      // Filter to only user's own hexes
      final mine = cells.where((c) => c.ownerId == profile.userId).toList();
      if (mounted && mine.isNotEmpty) {
        setState(() {
          _ownedHexBoundaries = mine.map((c) => c.boundary).toList();
        });
      }
    } catch (_) {}
  }

  /// Loads ALL owned hexes without depending on geolocation.
  /// Uses a wide bounding box covering the user's known territory.
  Future<void> _loadAllOwnedHexes() async {
    try {
      final profile = ref.read(userProfileProvider);
      if (profile.userId == null) return;
      final api = ref.read(apiServiceProvider);
      // Use a very wide search (whole city region)
      final cells = await api.getTerritories(
        minLat: 59.0,
        minLng: 17.8,
        maxLat: 59.5,
        maxLng: 18.3,
      );
      final mine = cells.where((c) => c.ownerId == profile.userId).toList();
      if (mounted && mine.isNotEmpty) {
        setState(() {
          _ownedHexBoundaries = mine.map((c) => c.boundary).toList();
        });
        // If geolocation failed, center map on owned hexes
        if (_initialPosition == null && mine.isNotEmpty) {
          final firstHex = mine.first.boundary;
          if (firstHex.isNotEmpty) {
            final center = firstHex[0];
            setState(() {
              _fallbackCenter = LatLng(center[0], center[1]);
            });
          }
        }
      }
    } catch (_) {}
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
    // Only follow during tracking if followUser is enabled
    final pos = widget.journey.currentPosition;
    if (pos != null && _mapReady && _followUser && pos.latitude.isFinite && pos.longitude.isFinite) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
    }
  }

  /// Called after claim submission — renders captured hexes on map
  void showCapturedHexes(List<List<List<double>>> boundaries) {
    setState(() => _capturedHexBoundaries = boundaries);
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
              if (pos.zoom != null && pos.zoom != _currentZoom) {
                setState(() => _currentZoom = pos.zoom!);
              }
              // User panned manually — disable auto-follow
              if (hasGesture && _followUser) {
                setState(() => _followUser = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.myloop.app',
            ),

            // User's owned hex polygons (animated overlay)
            if (_ownedHexBoundaries.isNotEmpty)
              AnimatedHexOverlay(
                hexBoundaries: _ownedHexBoundaries,
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

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              emoji: '⏱️',
              value: '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              label: 'Time',
            ),
            _StatItem(
              emoji: '📏',
              value: distanceKm >= 1
                  ? '${distanceKm.toStringAsFixed(1)} km'
                  : '${journey.distanceMeters.toInt()} m',
              label: 'Distance',
            ),
            _StatItem(
              emoji: '⬡',
              value: '—',
              label: 'Hexes',
            ),
          ],
        ),
      ),
    );
  }
}

/// A single stat column (emoji + value + label) used in [_StatsBar].
class _StatItem extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _StatItem({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.grey,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// BOTTOM CONTROLS
/// ─────────────────────────────────────────────────────────────────────────────

/// Bottom panel with Start/Stop buttons depending on journey state.
///
/// In idle state, shows "START JOURNEY" with instructions.
/// In tracking state, shows "STOP & CAPTURE" in red to end the walk.
class _BottomControls extends ConsumerWidget {
  final JourneyState journey;
  final JourneyController controller;
  final GlobalKey<_JourneyMapState> mapKey;
  const _BottomControls({required this.journey, required this.controller, required this.mapKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            ? _buildTrackingControls(context, ref)
            : _buildIdleControls(context),
      ),
    );
  }

  Widget _buildIdleControls(BuildContext context) {
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
          onPressed: () => controller.startJourney(),
        ),
      ],
    );
  }

  Widget _buildTrackingControls(BuildContext context, WidgetRef ref) {
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
          label: 'STOP & CAPTURE',
          icon: Icons.stop,
          color: AppColors.red,
          onPressed: () async {
            final path = controller.stopJourney();
            if (path.length < 2) {
              if (context.mounted) Navigator.of(context).pop();
              return;
            }
            // Submit claim to API and update user state
            try {
              final api = ref.read(apiServiceProvider);
              final profile = ref.read(userProfileProvider);
              if (profile.userId != null) {
                final result = await api.submitClaim(userId: profile.userId!, path: path);
                final capturedCount = (result['cellCount'] as num?)?.toInt() ?? 0;

                // Show captured hex boundaries on map
                final rawBoundaries = result['boundaries'] as List<dynamic>?;
                if (rawBoundaries != null && rawBoundaries.isNotEmpty) {
                  final boundaries = rawBoundaries.map<List<List<double>>>((b) =>
                    (b as List<dynamic>).map<List<double>>((point) =>
                      (point as List<dynamic>).map<double>((v) => (v as num).toDouble()).toList()
                    ).toList()
                  ).toList();
                  mapKey.currentState?.showCapturedHexes(boundaries);
                }

                // Refresh user stats from DB
                final user = await api.getUser(profile.userId!);
                ref.read(userProfileProvider.notifier).updateStats(
                  hexCount: user.hexCount,
                  streak: user.streak,
                  distanceKm: user.distanceKm,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Captured $capturedCount hexes! 🎉'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              }
            } catch (_) {
              // Silently fail — user can still see their walk ended
              if (context.mounted) Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }
}
