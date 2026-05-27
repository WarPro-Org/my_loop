import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/widgets/big_button.dart';

// Journey screen - shows the map with live hex capture
// User taps "Start" to begin walking, sees their path drawn in real-time
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journey = ref.watch(journeyControllerProvider);
    final controller = ref.read(journeyControllerProvider.notifier);

    // Show error as snackbar when it changes
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

// The map widget showing trail and hexes
class _JourneyMap extends StatelessWidget {
  final JourneyState journey;
  const _JourneyMap({required this.journey});

  @override
  Widget build(BuildContext context) {
    // Default center (will be overridden by GPS)
    final center = journey.currentPosition != null
        ? LatLng(
            journey.currentPosition!.latitude,
            journey.currentPosition!.longitude,
          )
        : const LatLng(28.6139, 77.2090); // Delhi fallback

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
      ),
      children: [
        // OpenStreetMap tiles (free)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.myloop.app',
        ),

        // Draw the walked path as a polyline
        if (journey.path.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: journey.path
                    .map((p) => LatLng(p[0], p[1]))
                    .toList(),
                color: AppColors.green,
                strokeWidth: 4,
              ),
            ],
          ),

        // Current position marker
        if (journey.currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  journey.currentPosition!.latitude,
                  journey.currentPosition!.longitude,
                ),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.green.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// Stats bar shown during tracking (distance, time, points)
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

// Bottom control panel (Start / Stop buttons)
class _BottomControls extends StatelessWidget {
  final JourneyState journey;
  final JourneyController controller;
  const _BottomControls({required this.journey, required this.controller});

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
            ? _buildTrackingControls(context)
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

  Widget _buildTrackingControls(BuildContext context) {
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
          onPressed: () {
            controller.stopJourney();
            // TODO: Submit path to API
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
