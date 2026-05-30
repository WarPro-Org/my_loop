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
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/user_state.dart';
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
              const SizedBox(height: 16),

              // Local account creation
              OutlinedButton(
                onPressed: () => context.push('/local-signup'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: const BorderSide(color: AppColors.greyLight, width: 2),
                ),
                child: const Text(
                  'CREATE ACCOUNT WITHOUT LOGIN',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.dark),
                ),
              ),
              const SizedBox(height: 12),

              // Dev skip button — only visible in debug mode
              if (const bool.fromEnvironment('dart.vm.product') == false)
                TextButton(
                  onPressed: () => _devSkip(context, ref),
                  child: Text(
                    'SKIP (DEV MODE)',
                    style: TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
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
  /// On success, checks if user already exists in DB. If so, loads profile
  /// and goes to /home. If not, navigates to /avatar for profile setup.
  Future<void> _signInWithGoogle(BuildContext context, WidgetRef ref) async {
    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithGoogle();
      if (user != null && context.mounted) {
        await _routeAfterAuth(context, ref, user.uid);
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
  /// On success, checks if user already exists in DB. If so, loads profile
  /// and goes to /home. If not, navigates to /avatar for profile setup.
  Future<void> _signInWithApple(BuildContext context, WidgetRef ref) async {
    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithApple();
      if (user != null && context.mounted) {
        await _routeAfterAuth(context, ref, user.uid);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  /// After successful auth, check if user is already registered.
  /// If yes → load profile and go home. If no → go to avatar picker.
  Future<void> _routeAfterAuth(BuildContext context, WidgetRef ref, String firebaseUid) async {
    try {
      final api = ref.read(apiServiceProvider);
      final existing = await api.getUserByUid(firebaseUid);
      if (existing != null && context.mounted) {
        ref.read(userProfileProvider.notifier).setFromApi(
          userId: existing.id,
          avatarId: existing.avatarId,
          color: existing.color,
          displayName: existing.displayName,
          hexCount: existing.hexCount,
          streak: existing.streak,
          distanceKm: existing.distanceKm,
        );
        context.go('/home');
        return;
      }
    } catch (_) {
      // API unreachable or user not found — proceed to avatar picker
    }
    if (context.mounted) context.go('/avatar');
  }
  }

  /// Dev mode: loads seeded "Robin" user from DB without Firebase auth.
  Future<void> _devSkip(BuildContext context, WidgetRef ref) async {
    try {
      final api = ref.read(apiServiceProvider);
      final user = await api.getUserByUid('uid_robin');
      if (user != null) {
        ref.read(userProfileProvider.notifier).setFromApi(
          userId: user.id,
          avatarId: user.avatarId,
          color: user.color,
          displayName: user.displayName,
          hexCount: user.hexCount,
          streak: user.streak,
          distanceKm: user.distanceKm,
        );
        // Fetch rank from leaderboard API
        final lb = await api.getLeaderboard(lat: 0, lng: 0, userId: user.id, scope: 'city');
        if (lb.myRank != null) {
          ref.read(userProfileProvider.notifier).updateStats(rank: lb.myRank);
        }
      }
      if (context.mounted) context.go('/home');
    } catch (e) {
      // If API is down, still navigate for testing
      if (context.mounted) context.go('/home');
    }
  }
}
