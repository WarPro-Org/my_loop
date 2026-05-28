/// Reusable call-to-action button styled after Duolingo's bold buttons.
///
/// Used throughout the app for primary actions: sign-in, start journey,
/// continue, etc. Features a 3D shadow effect and optional leading icon.
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';

/// A large, full-width rounded button with a 3D shadow effect.
///
/// Inspired by Duolingo's CTA buttons. The [color] defaults to the app's
/// primary green. The 3D depth is achieved by a darkened box shadow offset
/// below the button. Optionally displays an [icon] before the [label] text.
class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final IconData? icon;

  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.icon,
  });

  /// Builds the button with its 3D shadow container and inner ElevatedButton.
  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? AppColors.primary;
    // Derive a darker shade for the bottom shadow to create the 3D depth effect
    final darkColor = HSLColor.fromColor(btnColor)
        .withLightness(
          (HSLColor.fromColor(btnColor).lightness - 0.1).clamp(0, 1),
        )
        .toColor();

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: darkColor,
            offset: const Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
