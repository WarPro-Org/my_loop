/// Celebration dialog shown after a successful territory capture.
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';

class CelebrationDialog extends StatelessWidget {
  final int hexCount;
  final int stolenCount;
  final double distanceMeters;
  final Duration duration;
  final int streak;

  const CelebrationDialog({
    super.key,
    required this.hexCount,
    required this.stolenCount,
    required this.distanceMeters,
    required this.duration,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
            _StatRow(icon: '⬡', label: 'Hexes earned', value: '$hexCount'),
            if (stolenCount > 0)
              _StatRow(icon: '⚔️', label: 'Stolen from others', value: '$stolenCount'),
            _StatRow(icon: '📏', label: 'Distance walked', value: _formatDistance()),
            _StatRow(icon: '⏱️', label: 'Walk time', value: _formatDuration()),
            _StatRow(icon: '🔥', label: 'Current streak', value: '$streak day${streak == 1 ? '' : 's'}'),
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('AWESOME!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDistance() {
    return distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
        : '${distanceMeters.toStringAsFixed(0)} m';
  }

  String _formatDuration() {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
  }
}

class _StatRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  const _StatRow({required this.icon, required this.label, required this.value});

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
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
