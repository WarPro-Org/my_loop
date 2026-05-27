/// MyLoop — Application Routing Configuration
///
/// Declares the full navigation graph using `go_router`. The route structure
/// is organised into three tiers:
///
///   1. **Standalone routes** — full-screen pages with no persistent chrome
///      (login, avatar picker, journey recording).
///   2. **Shell route** — wraps the main tab scaffold ([HomeScreen]) so the
///      bottom navigation bar persists across child routes.
///   3. **Tab routes** — individual tabs rendered inside the shell (home,
///      leaderboard, profile).
///
/// Navigation triggers:
///   - After successful sign-in → `/avatar` (first-time) or `/home`.
///   - Bottom nav tap → switches between `/home`, `/leaderboard`, `/profile`.
///   - "Start Journey" button on HomeTab → pushes `/journey`.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/auth/login_screen.dart';
import 'package:myloop/features/auth/avatar_picker_screen.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/features/home/home_tab.dart';
import 'package:myloop/features/journey/journey_screen.dart';
import 'package:myloop/features/leaderboard/leaderboard_screen.dart';
import 'package:myloop/features/profile/profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Transition Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a [CustomTransitionPage] with **no animation**.
///
/// Used for tab routes inside the [ShellRoute] so switching between bottom-nav
/// tabs feels instantaneous rather than sliding or fading. Without this, each
/// tab change would play the default platform transition which feels sluggish
/// in a tabbed interface.
///
/// Parameters:
/// - [child] — the screen widget to display.
/// - [state] — the current [GoRouterState], used to derive [pageKey].
CustomTransitionPage _noTransitionPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    // Return the child directly without wrapping in an animated builder.
    transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Router Definition
// ─────────────────────────────────────────────────────────────────────────────

/// The global [GoRouter] instance consumed by [MaterialApp.router].
///
/// Initial location is `/login` — the auth flow acts as a gate before any
/// authenticated content is reachable. A redirect guard could be added here
/// to automatically send authenticated users to `/home`.
final router = GoRouter(
  initialLocation: '/login',
  routes: [
    // ── Authentication Flow ────────────────────────────────────────────────

    /// Login screen — entry point for unauthenticated users.
    /// Offers Google and Apple sign-in options.
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    /// Avatar picker — shown after first-time sign-up so the user can
    /// choose a profile avatar before entering the main experience.
    GoRoute(
      path: '/avatar',
      builder: (context, state) => const AvatarPickerScreen(),
    ),

    // ── Main Tab Shell ─────────────────────────────────────────────────────

    /// Shell route wrapping [HomeScreen] which provides the persistent
    /// bottom navigation bar. Child routes are rendered inside the shell's
    /// `child` slot while the nav bar stays visible.
    ShellRoute(
      builder: (context, state, child) => HomeScreen(child: child),
      routes: [
        /// Home tab — the default landing tab showing the map, territory
        /// stats, and the "Start Journey" call-to-action.
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              _noTransitionPage(const HomeTab(), state),
        ),

        /// Leaderboard tab — displays ranked list of users by territory
        /// claimed, with weekly/all-time toggle.
        GoRoute(
          path: '/leaderboard',
          pageBuilder: (context, state) =>
              _noTransitionPage(const LeaderboardScreen(), state),
        ),

        /// Profile tab — shows the current user's stats, avatar, and
        /// sign-out option.
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) =>
              _noTransitionPage(const ProfileScreen(), state),
        ),
      ],
    ),

    // ── Full-Screen Overlays ───────────────────────────────────────────────

    /// Journey recording screen — pushed on top of the tab shell so the
    /// bottom nav is hidden during an active journey. Uses the default
    /// platform transition (slide up on iOS, fade on Android).
    GoRoute(
      path: '/journey',
      builder: (context, state) => const JourneyScreen(),
    ),
  ],
);
