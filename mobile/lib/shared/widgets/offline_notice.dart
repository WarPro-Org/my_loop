/// A centered "you're offline" placeholder.
///
/// Shown in place of a list/empty state when a fetch failed because the
/// backend was unreachable (see [isServerUnreachable]). This makes the offline
/// condition explicit instead of letting the screen render a misleading
/// "no data" empty state or a zeroed-out value (issue #36).
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/widgets/retry_button.dart';

class OfflineNotice extends StatelessWidget {
  /// Short headline, e.g. "You're offline".
  final String title;

  /// Explanatory line telling the user what to do.
  final String message;

  /// When provided, an in-place retry control is rendered below the message so
  /// the user can re-attempt the failed fetch once back online (issue #49).
  final VoidCallback? onRetry;

  const OfflineNotice(
      {super.key, required this.title, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: AppColors.greyLight),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey, fontSize: 13),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              RetryButton(onPressed: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}
