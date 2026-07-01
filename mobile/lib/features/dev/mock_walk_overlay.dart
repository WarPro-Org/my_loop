/// MyLoop — Mock Walk Simulation: on-screen debug overlay (#29 follow-up)
///
/// Compact panel shown only while a debug mock walk is running. Before the walk
/// finishes it is a live HUD (fix N/total, %, elapsed/ETA, speed, retained/raw);
/// once the synthetic stream ends it becomes a counts-only result summary so a
/// desk tester sees the outcome without reading logs.
///
/// Pure observer — it reads [mockWalkProgressProvider] + [journeyControllerProvider]
/// and writes nothing back into the GPS stream. Callers gate it behind
/// `kDebugMode` so it never ships in a release build.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/services/mock/mock_walk_progress.dart';

class MockWalkOverlay extends ConsumerWidget {
  const MockWalkOverlay({super.key});

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(mockWalkProgressProvider);
    final journey = ref.watch(journeyControllerProvider);
    if (!progress.isActive) return const SizedBox.shrink();

    final retained = journey.path.length;
    final rows = progress.finished
        ? _summaryRows(journey, progress, retained)
        : _hudRows(journey, progress, retained);

    return Container(
      width: 188,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            progress.finished ? 'MOCK WALK — RESULT' : 'MOCK WALK — LIVE',
            style: const TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
                fontSize: 11),
          ),
          const SizedBox(height: 6),
          if (!progress.finished) ...[
            LinearProgressIndicator(value: progress.fraction, minHeight: 4),
            const SizedBox(height: 6),
          ],
          ...rows,
        ],
      ),
    );
  }

  List<Widget> _hudRows(JourneyState journey, MockWalkProgress p, int retained) {
    return [
      _row('Fix', '${p.emitted} / ${p.total}'),
      _row('Done', '${(p.fraction * 100).toStringAsFixed(0)}%'),
      _row('Time', '${_clock(p.elapsed)} / ${_clock(p.eta)}'),
      _row('Speed',
          '${journey.currentPosition?.speed.toStringAsFixed(1) ?? '–'} m/s'),
      _row('Pts', '$retained ret / ${p.emitted} raw'),
    ];
  }

  List<Widget> _summaryRows(
      JourneyState journey, MockWalkProgress p, int retained) {
    final ok = journey.rejectionCount == 0 && journey.claimedCount > 0;
    return [
      _row('Claimed', '${journey.claimedCount} hexes'),
      _row('Rejected', '${journey.rejectionCount}'),
      _row('Pts', '$retained ret / ${p.emitted} raw'),
      const SizedBox(height: 4),
      Text(
        ok ? 'STATUS: OK' : 'STATUS: CHECK',
        style: TextStyle(
          color: ok ? Colors.greenAccent : Colors.orangeAccent,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      if (journey.rejectionCount > 0 && journey.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(journey.error!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
        ),
    ];
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
