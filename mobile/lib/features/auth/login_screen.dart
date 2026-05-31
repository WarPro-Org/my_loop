/// Login screen — the app's entry point for unauthenticated users.
///
/// Presents a Duolingo-inspired welcome page with a mascot emoji, app
/// branding, and OAuth sign-in buttons (Google & Apple). On successful
/// authentication, navigates to the avatar picker screen.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/big_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// The initial login/welcome screen shown to unauthenticated users.
///
/// Follows a simple vertical layout: mascot, branding, spacer, CTA buttons,
/// and legal text. On startup, if a Firebase session is already restored
/// (e.g., after an app restart), the user is automatically routed to /home
/// without seeing the login UI.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _autoSigningIn = false;

  @override
  void initState() {
    super.initState();
    // After first frame: check whether Firebase already has a restored session.
    // This fires every time the login screen mounts (e.g., after app restart).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authService = ref.read(authServiceProvider);
      final currentUser = authService.currentUser;
      if (currentUser != null) {
        setState(() => _autoSigningIn = true);
        _routeAfterAuth(currentUser.uid);
      }
    });
  }

  /// Builds the full-screen login layout with branding and sign-in CTAs.
  @override
  Widget build(BuildContext context) {
    // While auto-routing an already-authenticated session, show a spinner
    // so the login buttons never flash on screen.
    if (_autoSigningIn) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
                onPressed: () => _signInWithGoogle(),
              ),
              const SizedBox(height: 12),

              // Apple sign in button
              BigButton(
                label: 'CONTINUE WITH APPLE',
                icon: Icons.apple,
                color: AppColors.dark,
                onPressed: () => _signInWithApple(),
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
                  onPressed: () => _devSkip(),
                  child: Text(
                    'SKIP (DEV MODE)',
                    style: TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                ),

              const Spacer(flex: 1),

              // Terms text with tappable links
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.grey,
                    fontSize: 12,
                  ),
                  children: [
                    const TextSpan(text: 'By continuing, you agree to our '),
                    TextSpan(
                      text: 'Terms',
                      style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
                      recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse('https://destitute-living-bullpen.ngrok-free.dev/terms')),
                    ),
                    const TextSpan(text: ' & '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
                      recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse('https://destitute-living-bullpen.ngrok-free.dev/privacy')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithGoogle();
      if (user != null && mounted) {
        await _routeAfterAuth(user.uid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  Future<void> _signInWithApple() async {
    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithApple();
      if (user != null && mounted) {
        await _routeAfterAuth(user.uid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  /// After auth (fresh or restored session): load profile and go to /home,
  /// or go to /avatar if this is a new user.
  Future<void> _routeAfterAuth(String firebaseUid) async {
    try {
      final api = ref.read(apiServiceProvider);
      final existing = await api.getUserByUid(firebaseUid);
      if (existing != null && mounted) {
        // Fetch rank while we have the API connection
        int rank = 0;
        try {
          final lb = await api.getLeaderboard(lat: 0, lng: 0, userId: existing.id, scope: 'city');
          rank = lb.myRank ?? 0;
        } catch (_) {}

        ref.read(userProfileProvider.notifier).setFromApi(
          userId: existing.id,
          avatarId: existing.avatarId,
          color: existing.color,
          displayName: existing.displayName,
          hexCount: existing.hexCount,
          streak: existing.streak,
          distanceKm: existing.distanceKm,
          rank: rank,
        );
        if (mounted) context.go('/home');
        return;
      }
    } catch (_) {
      // API unreachable or user not found — proceed to avatar picker
    }
    if (mounted) {
      setState(() => _autoSigningIn = false);
      context.go('/avatar');
    }
  }

  Future<void> _devSkip() async {
    try {
      final api = ref.read(apiServiceProvider);
      final user = await api.getUserByUid('uid_robin');
      if (user != null) {
        int rank = 0;
        try {
          final lb = await api.getLeaderboard(lat: 0, lng: 0, userId: user.id, scope: 'city');
          rank = lb.myRank ?? 0;
        } catch (_) {}

        ref.read(userProfileProvider.notifier).setFromApi(
          userId: user.id,
          avatarId: user.avatarId,
          color: user.color,
          displayName: user.displayName,
          hexCount: user.hexCount,
          streak: user.streak,
          distanceKm: user.distanceKm,
          rank: rank,
        );
      }
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) context.go('/home');
    }
  }
}
