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
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  /// Builds the stacked layout: map → stats overlay → bottom controls.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          _JourneyMap(journey: journey),

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
  const _JourneyMap({required this.journey});

  @override
  ConsumerState<_JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends ConsumerState<_JourneyMap> {
  final MapController _mapController = MapController();
  Position? _initialPosition;
  Timer? _locationTimer;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _acquireLocation();
    // Auto-update position every 5 seconds when not tracking
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
      if (mounted) {
        setState(() => _initialPosition = pos);
        if (_mapReady) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 17);
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshPosition() async {
    // Only auto-refresh when NOT already tracking (controller handles that)
    final journey = ref.read(journeyControllerProvider);
    if (journey.status == JourneyStatus.tracking) return;
    try {
      final locationService = ref.read(locationServiceProvider);
      final pos = await locationService.getCurrentPosition();
      if (mounted) {
        setState(() => _initialPosition = pos);
        if (_mapReady) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
        }
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _JourneyMap old) {
    super.didUpdateWidget(old);
    // Follow user during tracking
    final pos = widget.journey.currentPosition;
    if (pos != null && _mapReady) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final profile = ref.watch(userProfileProvider);

    // Determine map center
    LatLng center;
    if (journey.currentPosition != null) {
      center = LatLng(journey.currentPosition!.latitude, journey.currentPosition!.longitude);
    } else if (_initialPosition != null) {
      center = LatLng(_initialPosition!.latitude, _initialPosition!.longitude);
    } else {
      center = const LatLng(0, 0); // Will be updated once GPS resolves
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 17,
        onMapReady: () {
          _mapReady = true;
          // If we already have a position, snap to it
          if (_initialPosition != null) {
            _mapController.move(LatLng(_initialPosition!.latitude, _initialPosition!.longitude), 17);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.myloop.app',
        ),

        // Draw the walked path as a polyline
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
        if (journey.currentPosition != null || _initialPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: journey.currentPosition != null
                    ? LatLng(journey.currentPosition!.latitude, journey.currentPosition!.longitude)
                    : LatLng(_initialPosition!.latitude, _initialPosition!.longitude),
                width: 44,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
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
    final points = journey.path.length;

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
              emoji: '📍',
              value: '$points',
              label: 'Points',
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
  const _BottomControls({required this.journey, required this.controller});

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
            }
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
