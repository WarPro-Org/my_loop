/// Login screen — the app's entry point for unauthenticated users.
///
/// Presents a Duolingo-inspired welcome page with a mascot emoji, app
/// branding, and OAuth sign-in buttons (Google & Apple). On successful
/// authentication, navigates to the avatar picker screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/widgets/big_button.dart';

/// The initial login/welcome screen shown to unauthenticated users.
///
/// Follows a simple vertical layout: mascot, branding, spacer, CTA buttons,
/// and legal text. Uses [ConsumerWidget] to access the auth service via
/// Riverpod for sign-in operations.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  /// Builds the full-screen login layout with branding and sign-in CTAs.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Big mascot/logo
              const Text('🌍', style: TextStyle(fontSize: 80)),
              const SizedBox(height: 16),

              // App name
              Text(
                'MyLoop',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),

              // Tagline
              Text(
                'Walk. Capture. Conquer.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.grey,
                ),
              ),

              const Spacer(flex: 3),

              // Google sign in button
              BigButton(
                label: 'CONTINUE WITH GOOGLE',
                icon: Icons.login,
                onPressed: () => _signInWithGoogle(context, ref),
              ),
              const SizedBox(height: 12),

              // Apple sign in button
              BigButton(
                label: 'CONTINUE WITH APPLE',
                icon: Icons.apple,
                color: AppColors.dark,
                onPressed: () => _signInWithApple(context, ref),
              ),

              const Spacer(flex: 1),

              // Terms text
              Text(
                'By continuing, you agree to our Terms & Privacy Policy',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.grey,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Initiates Google OAuth sign-in flow.
  ///
  /// On success, navigates to `/avatar` for profile setup.
  /// On failure, shows an error snackbar.
  Future<void> _signInWithGoogle(BuildContext context, WidgetRef ref) async {
    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithGoogle();
      if (user != null && context.mounted) {
        context.go('/avatar');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  /// Initiates Apple Sign-In flow.
  ///
  /// On success, navigates to `/avatar` for profile setup.
  /// On failure, shows an error snackbar.
  Future<void> _signInWithApple(BuildContext context, WidgetRef ref) async {
    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithApple();
      if (user != null && context.mounted) {
        context.go('/avatar');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }
}
