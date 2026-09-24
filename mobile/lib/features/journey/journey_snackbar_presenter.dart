/// Turns the journey's one-shot messages into snackbars (#139 D5).
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/journey/journey_controller.dart';

/// Shows [JourneyState]'s one-shot `error`, `levelUpTo` and
/// `achievementUnlocked` as snackbars, without letting one message destroy
/// another.
///
/// Two rules, and they pull in opposite directions:
///
/// * **Celebrations queue.** One batch can level the player up AND unlock an
///   achievement in a single transition (`_onBatchResult` sets both in one
///   `copyWith`), and `BatchDrainService` drains batches back to back, so a
///   rejection can arrive milliseconds after a level-up. `clearSnackBars()`
///   empties the whole queue, so calling it for any message used to throw away a
///   level-up the player had earned before it was ever painted.
/// * **Errors are latest-wins.** Only the newest rejection reason is worth
///   reading, so at most one error snackbar is ever pending. A newer error closes
///   the visible error, or rewrites the text of the queued one, and never touches
///   anything else in the queue.
///
/// Owned by the journey screen's `State`, since it remembers the pending error
/// across transitions.
class JourneySnackbarPresenter {
  static const levelUpColor = Color(0xFFFFD700);
  static const achievementColor = Color(0xFF8B5CF6);

  static String levelUpMessage(int level) => '🎉 Level Up! You reached Level $level!';
  static String achievementMessage(String name) => '🏆 Achievement: $name';

  _PendingError? _pendingError;

  /// Surfaces whatever one-shot messages [next] carries that [prev] did not.
  ///
  /// Keyed on inequality, which is why `copyWith` must keep clearing these
  /// fields: a sticky value would make an identical repeat compare equal.
  void onJourneyChanged(
    ScaffoldMessengerState messenger,
    JourneyState? prev,
    JourneyState next,
  ) {
    final error = next.error;
    if (error != null && error != prev?.error) showError(messenger, error);

    final level = next.levelUpTo;
    if (level != null && level != prev?.levelUpTo) {
      showNotice(messenger, levelUpMessage(level), levelUpColor);
    }

    final achievement = next.achievementUnlocked;
    if (achievement != null && achievement != prev?.achievementUnlocked) {
      showNotice(messenger, achievementMessage(achievement), achievementColor);
    }
  }

  /// Queues a celebration or hint behind whatever is already showing or queued.
  void showNotice(ScaffoldMessengerState messenger, String message, Color color) {
    messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  /// Shows [message] as the single pending error, replacing only an earlier
  /// error.
  void showError(ScaffoldMessengerState messenger, String message) {
    final pending = _pendingError;
    if (pending != null && !pending.visible) {
      // Still waiting behind a celebration. A queued snackbar cannot be pulled
      // out of the messenger, so rewrite what it will say instead.
      pending.text.value = message;
      return;
    }
    if (pending != null) {
      // onVisible fired and closed has not, so the current snackbar is this
      // error: hiding the current one cannot touch a celebration.
      _pendingError = null;
      messenger.hideCurrentSnackBar();
    }

    final entry = _PendingError(ValueNotifier(message));
    _pendingError = entry;
    messenger
        .showSnackBar(SnackBar(
          content: ValueListenableBuilder<String>(
            valueListenable: entry.text,
            builder: (_, text, _) => Text(text),
          ),
          backgroundColor: AppColors.red,
          onVisible: () => entry.visible = true,
        ))
        .closed
        .whenComplete(() {
      if (identical(_pendingError, entry)) _pendingError = null;
      // Safe even if the builder has not unmounted yet: removeListener returns
      // immediately on a disposed notifier.
      entry.text.dispose();
    });
  }
}

/// The one error snackbar that has been shown or queued and not yet closed.
class _PendingError {
  _PendingError(this.text);

  final ValueNotifier<String> text;

  /// True once the snackbar has finished its entrance, i.e. it is the
  /// messenger's current snackbar until it closes.
  bool visible = false;
}
