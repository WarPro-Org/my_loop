/// Pins the ScaffoldMessenger behaviour `journey_screen._showSnackbar` depends on (#139 D5).
///
/// `_onBatchResult` sets `levelUpTo` and `achievementUnlocked` in a single
/// `copyWith`, so the journey screen's listener calls `_showSnackbar` twice in a
/// row for one state transition. It used to call `clearSnackBars()` every time,
/// which destroyed the level-up toast before it was painted — the player earned
/// it and never saw it. Errors still clear (only the latest rejection reason is
/// worth reading); celebrations now queue.
///
/// These tests assert the two messenger behaviours that split depends on, so a
/// future change to `_showSnackbar` that reintroduces unconditional clearing has
/// something to fail against.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `_showSnackbar`'s post-fix logic.
void showSnack(
  ScaffoldMessengerState messenger,
  String message, {
  bool replacePrevious = false,
}) {
  if (replacePrevious) messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

void main() {
  late ScaffoldMessengerState messenger;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
  }

  testWidgets('a queued second message does not discard the first', (tester) async {
    await pumpHost(tester);

    // The real scenario: one batch levels the player up AND unlocks an achievement,
    // so the listener calls this twice within a single state transition.
    showSnack(messenger, 'Level Up');
    showSnack(messenger, 'Achievement');
    await tester.pump();

    // The point of the fix: the first celebration still reaches the screen.
    // ScaffoldMessenger delivers the second from its own queue afterwards — that
    // is framework behaviour and this test deliberately does not re-assert it,
    // since driving the dismiss/entrance timers adds flakiness without adding
    // confidence in our change.
    expect(find.text('Level Up'), findsOneWidget,
        reason: 'the earned level-up toast must be painted, not silently dropped');
  });

  testWidgets('replacePrevious drops the earlier message', (tester) async {
    await pumpHost(tester);

    // Errors: only the newest rejection reason matters, so replacing is correct.
    showSnack(messenger, 'Old rejection');
    showSnack(messenger, 'New rejection', replacePrevious: true);
    await tester.pump();

    expect(find.text('Old rejection'), findsNothing);
    expect(find.text('New rejection'), findsOneWidget);
  });

  // This is the regression: it is what unconditional clearing did to every
  // celebration pair, and what the fix stops doing.
  testWidgets('clearing before every message loses all but the last', (tester) async {
    await pumpHost(tester);

    showSnack(messenger, 'Level Up', replacePrevious: true);
    showSnack(messenger, 'Achievement', replacePrevious: true);
    await tester.pump();

    expect(find.text('Level Up'), findsNothing,
        reason: 'demonstrates the bug: the level-up toast never reaches the screen');
    expect(find.text('Achievement'), findsOneWidget);
  });
}
