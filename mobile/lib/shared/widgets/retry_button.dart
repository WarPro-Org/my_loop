/// Shared in-place retry control for offline-recovery affordances.
///
/// Rendered by offline placeholders ([OfflineNotice] and the rank sheet's
/// offline note) so a user can re-attempt the failed fetch once connectivity
/// returns, without navigating away from the screen (issue #49). Keeping this a
/// single widget gives both surfaces one consistent affordance.
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/constants/app_constants.dart';

class RetryButton extends StatelessWidget {
  /// Invoked when the user taps the control — should re-run the failed fetch.
  final VoidCallback onPressed;

  const RetryButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, size: 18, color: AppColors.primary),
      label: const Text(
        AppConstants.retryButtonLabel,
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
