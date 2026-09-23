/// Locks in `JourneyState.copyWith`'s one-shot fields (#139 D5).
///
/// `error`, `levelUpTo` and `achievementUnlocked` are assigned bare rather than
/// `x ?? this.x`, so a copy that does not re-supply them clears them. The debt
/// register flagged that as "implicit one-shot semantics, easy to lose a
/// rejection message on the next GPS tick".
///
/// The state layer does not lose it: `journey_screen` surfaces all three
/// through a listener (`JourneySnackbarPresenter.onJourneyChanged`) guarded on `next.x != prev?.x`, and Riverpod fires that listener
/// synchronously on each state assignment, so the snackbar is shown before the
/// next tick clears it. The clearing is in fact required — without it a second
/// *identical* message would compare equal to the previous value and be
/// suppressed.
///
/// These tests exist so that the tempting "cleanup" to `?? this.error` fails
/// here instead of silently swallowing a repeated rejection in production.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/features/journey/journey_controller.dart';

void main() {
  group('one-shot fields clear on an unrelated copy', () {
    test('error does not survive a copy that omits it', () {
      const withError = JourneyState(error: 'Movement speed exceeds physical limits');
      // A GPS tick copies with only positional data.
      final afterTick = withError.copyWith(distanceMeters: 12.5);
      expect(afterTick.error, isNull,
          reason: 'clearing is what lets an identical repeat be seen as a change');
      expect(afterTick.distanceMeters, 12.5);
    });

    test('levelUpTo does not survive a copy that omits it', () {
      const leveled = JourneyState(levelUpTo: 7);
      expect(leveled.copyWith(distanceMeters: 1).levelUpTo, isNull);
    });

    test('achievementUnlocked does not survive a copy that omits it', () {
      const unlocked = JourneyState(achievementUnlocked: 'First Loop');
      expect(unlocked.copyWith(distanceMeters: 1).achievementUnlocked, isNull);
    });
  });

  group('everything else is sticky', () {
    test('cumulative and positional fields survive an unrelated copy', () {
      const seeded = JourneyState(
        distanceMeters: 100,
        loopCount: 2,
        claimedCount: 5,
        xpGainedThisWalk: 40,
        rejectionCount: 3,
        lastStolenFrom: 'Robin',
      );
      final copied = seeded.copyWith(elapsed: const Duration(seconds: 30));

      expect(copied.distanceMeters, 100);
      expect(copied.loopCount, 2);
      expect(copied.claimedCount, 5);
      expect(copied.xpGainedThisWalk, 40);
      expect(copied.lastStolenFrom, 'Robin');
      expect(copied.elapsed, const Duration(seconds: 30));
    });

    // rejectionCount is the durable counterpart to the transient `error`, so a
    // consumer that reads during build has something that does not evaporate.
    test('rejectionCount is cumulative, unlike error', () {
      const state = JourneyState(rejectionCount: 3, error: 'rejected');
      final afterTick = state.copyWith(distanceMeters: 1);
      expect(afterTick.rejectionCount, 3);
      expect(afterTick.error, isNull);
    });
  });

  // The scenario the one-shot shape protects: the same rejection reason twice.
  // journey_screen's guard is `next.error != prev?.error`, so without the clear
  // in between the second occurrence would be suppressed.
  test('an identical message repeats as a distinct transition', () {
    const message = 'Movement speed exceeds physical limits';

    const first = JourneyState(error: message);
    final cleared = first.copyWith(distanceMeters: 5); // GPS tick
    final second = cleared.copyWith(error: message);

    expect(first.error, message);
    expect(cleared.error, isNull);
    expect(second.error, message);
    // Each arrival differs from the state before it, which is what the screen's
    // listener keys on. Were error sticky, second.error == first.error and the
    // repeat would never be shown.
    expect(second.error, isNot(cleared.error));
  });
}
