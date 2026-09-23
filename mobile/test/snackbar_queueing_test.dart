/// Drives `JourneySnackbarPresenter` — the code `JourneyScreen`'s listener
/// delegates to — with real `JourneyState` transitions (#139 D5).
///
/// Two ways a celebration used to be lost:
/// * one batch sets `levelUpTo` and `achievementUnlocked` in a single
///   `copyWith`, and clearing before every snackbar destroyed the level-up;
/// * `BatchDrainService` drains batches back to back, so a rejection can land
///   milliseconds after a level-up, and clearing for the error wiped the queue.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/journey_controller.dart';
import 'package:myloop/features/journey/journey_snackbar_presenter.dart';

/// Long enough for any snackbar's entrance animation to complete, well short of
/// the default 4 s display time.
const _settle = Duration(milliseconds: 500);

/// Longer than a snackbar's display time plus its exit and the next entrance.
const _nextSnackbar = Duration(seconds: 5);

/// Advances the clock frame by frame, so timers fire AND the exit/entrance
/// animations they start actually run (one big `pump` would do only one frame).
Future<void> _advance(WidgetTester tester, Duration total) async {
  const frame = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += frame) {
    await tester.pump(frame);
  }
}

void main() {
  late ScaffoldMessengerState messenger;
  late JourneySnackbarPresenter presenter;

  final levelUpText = JourneySnackbarPresenter.levelUpMessage(7);
  final achievementText = JourneySnackbarPresenter.achievementMessage('First Loop');

  Future<void> pumpHost(WidgetTester tester) async {
    presenter = JourneySnackbarPresenter();
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

  testWidgets('a level-up and an achievement in one transition are both shown', (tester) async {
    await pumpHost(tester);

    // What _onBatchResult emits: both celebrations in a single copyWith.
    presenter.onJourneyChanged(
      messenger,
      const JourneyState(),
      const JourneyState(levelUpTo: 7, achievementUnlocked: 'First Loop'),
    );
    await tester.pump();
    await _advance(tester, _settle);

    expect(find.text(levelUpText), findsOneWidget,
        reason: 'the earned level-up must be painted, not cleared by the achievement');

    await _advance(tester, _nextSnackbar);
    await _advance(tester, _settle);
    expect(find.text(achievementText), findsOneWidget,
        reason: 'the achievement is queued behind the level-up, not dropped');
  });

  testWidgets('a rejection right after a level-up does not wipe the level-up', (tester) async {
    await pumpHost(tester);

    const leveled = JourneyState(levelUpTo: 7, achievementUnlocked: 'First Loop');
    presenter.onJourneyChanged(messenger, const JourneyState(), leveled);
    // The next batch in the same drain is rejected before the toast has settled.
    await tester.pump();
    presenter.onJourneyChanged(
      messenger,
      leveled,
      const JourneyState(error: 'Movement speed exceeds physical limits'),
    );
    await tester.pump();
    await _advance(tester, _settle);

    expect(find.text(levelUpText), findsOneWidget,
        reason: 'an error must not clear the celebration queue');

    await _advance(tester, _nextSnackbar);
    await _advance(tester, _settle);
    expect(find.text(achievementText), findsOneWidget);

    await _advance(tester, _nextSnackbar);
    await _advance(tester, _settle);
    expect(find.text('Movement speed exceeds physical limits'), findsOneWidget,
        reason: 'the rejection still reaches the player, after the celebrations');
  });

  testWidgets('a newer error replaces the visible error', (tester) async {
    await pumpHost(tester);

    presenter.showError(messenger, 'Old rejection');
    await tester.pump();
    await _advance(tester, _settle);
    expect(find.text('Old rejection'), findsOneWidget);

    presenter.showError(messenger, 'New rejection');
    await tester.pump();
    await _advance(tester, _settle);
    await _advance(tester, _settle);

    expect(find.text('Old rejection'), findsNothing);
    expect(find.text('New rejection'), findsOneWidget);
  });

  testWidgets('replacing a visible error keeps a celebration queued behind it', (tester) async {
    await pumpHost(tester);

    presenter.showError(messenger, 'Old rejection');
    await tester.pump();
    await _advance(tester, _settle);
    presenter.showNotice(messenger, levelUpText, JourneySnackbarPresenter.levelUpColor);
    presenter.showError(messenger, 'New rejection');
    await tester.pump();
    await _advance(tester, _settle);
    await _advance(tester, _settle);

    expect(find.text('Old rejection'), findsNothing);
    expect(find.text(levelUpText), findsOneWidget,
        reason: 'only the error is replaced; the queued level-up moves up');

    await _advance(tester, _nextSnackbar);
    await _advance(tester, _settle);
    expect(find.text('New rejection'), findsOneWidget);
  });

  testWidgets('errors queued behind a celebration collapse to the latest', (tester) async {
    await pumpHost(tester);

    presenter.showNotice(messenger, levelUpText, JourneySnackbarPresenter.levelUpColor);
    presenter.showError(messenger, 'First rejection');
    presenter.showError(messenger, 'Second rejection');
    await tester.pump();
    await _advance(tester, _settle);
    expect(find.text(levelUpText), findsOneWidget);

    await _advance(tester, _nextSnackbar);
    await _advance(tester, _settle);
    expect(find.text('First rejection'), findsNothing);
    expect(find.text('Second rejection'), findsOneWidget);

    // And nothing else was queued behind it: the error was rewritten, not added.
    await _advance(tester, _nextSnackbar);
    await _advance(tester, _settle);
    expect(find.byType(SnackBar), findsNothing);
  });
}
