/// Widget tests for the debug mock-walk overlay (#29 follow-up).
///
/// The overlay is pure presentation over two providers, so these seed each
/// provider to a fixed state and assert the rendered read-out: the live HUD while
/// a run is in flight, and the counts-only OK / CHECK summary once it finishes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/dev/mock_walk_overlay.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/shared/services/mock/mock_walk_progress.dart';

/// Returns a fixed [JourneyState] regardless of controller logic.
class _FakeJourney extends JourneyController {
  _FakeJourney(this._seed);
  final JourneyState _seed;
  @override
  JourneyState build() => _seed;
}

/// Returns a fixed [MockWalkProgress] snapshot.
class _FakeProgress extends MockWalkProgressNotifier {
  _FakeProgress(this._seed);
  final MockWalkProgress _seed;
  @override
  MockWalkProgress build() => _seed;
}

Future<void> _pump(
  WidgetTester tester, {
  required MockWalkProgress progress,
  required JourneyState journey,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        mockWalkProgressProvider.overrideWith(() => _FakeProgress(progress)),
        journeyControllerProvider.overrideWith(() => _FakeJourney(journey)),
      ],
      child: const MaterialApp(home: Scaffold(body: MockWalkOverlay())),
    ),
  );
}

void main() {
  testWidgets('renders nothing when no run is active', (tester) async {
    await _pump(tester,
        progress: const MockWalkProgress(), journey: const JourneyState());
    expect(find.textContaining('MOCK WALK'), findsNothing);
  });

  testWidgets('shows the live HUD with fix progress mid-run', (tester) async {
    await _pump(
      tester,
      progress: MockWalkProgress(total: 10, emitted: 3, startedAt: DateTime.now()),
      journey: JourneyState(
        status: JourneyStatus.tracking,
        path: List.generate(4, (_) => [0.0, 0.0]),
      ),
    );
    expect(find.text('MOCK WALK — LIVE'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
  });

  testWidgets('shows an OK summary once finished with claims and no rejections',
      (tester) async {
    await _pump(
      tester,
      progress: MockWalkProgress(
          total: 40, emitted: 40, startedAt: DateTime.now(), finished: true),
      journey: JourneyState(
        status: JourneyStatus.tracking,
        claimedCount: 23,
        path: List.generate(41, (_) => [0.0, 0.0]),
      ),
    );
    expect(find.text('MOCK WALK — RESULT'), findsOneWidget);
    expect(find.text('23 hexes'), findsOneWidget);
    expect(find.text('STATUS: OK'), findsOneWidget);
  });

  testWidgets('flags CHECK when a batch was rejected', (tester) async {
    await _pump(
      tester,
      progress: const MockWalkProgress(total: 40, emitted: 40, finished: true),
      journey: const JourneyState(
        status: JourneyStatus.tracking,
        claimedCount: 5,
        rejectionCount: 2,
        error: 'batch rejected: speed too high',
      ),
    );
    expect(find.text('STATUS: CHECK'), findsOneWidget);
    expect(find.textContaining('speed too high'), findsOneWidget);
  });
}
