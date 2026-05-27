import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/auth/login_screen.dart';
import 'package:myloop/features/auth/avatar_picker_screen.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/features/home/home_tab.dart';
import 'package:myloop/features/journey/journey_screen.dart';
import 'package:myloop/features/leaderboard/leaderboard_screen.dart';
import 'package:myloop/features/profile/profile_screen.dart';

// No animation for tab switches inside the shell
CustomTransitionPage _noTransitionPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

// All app routes defined in one place
final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/avatar',
      builder: (context, state) => const AvatarPickerScreen(),
    ),
    // Main app shell with bottom nav
    ShellRoute(
      builder: (context, state, child) => HomeScreen(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => _noTransitionPage(const HomeTab(), state),
        ),
        GoRoute(
          path: '/leaderboard',
          pageBuilder: (context, state) => _noTransitionPage(const LeaderboardScreen(), state),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => _noTransitionPage(const ProfileScreen(), state),
        ),
      ],
    ),
    GoRoute(
      path: '/journey',
      builder: (context, state) => const JourneyScreen(),
    ),
  ],
);
