/// MyLoop - Application Routing Configuration
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/features/auth/login_screen.dart';
import 'package:myloop/features/auth/avatar_picker_screen.dart';
import 'package:myloop/features/auth/local_signup_screen.dart';
import 'package:myloop/features/auth/set_home_screen.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/features/home/home_tab.dart';
import 'package:myloop/features/journey/journey_screen.dart';
import 'package:myloop/features/leaderboard/leaderboard_screen.dart';
import 'package:myloop/features/achievements/achievements_screen.dart';
import 'package:myloop/features/profile/profile_screen.dart';
import 'package:myloop/features/profile/user_profile_screen.dart';
import 'package:myloop/features/history/walk_history_screen.dart';
import 'package:myloop/features/notifications/notifications_screen.dart';

/// No-animation page transition for tab switches.
CustomTransitionPage _noTransitionPage(Widget child, GoRouterState state, String tabKey) {
  return CustomTransitionPage(
    key: ValueKey(tabKey),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

/// The global router instance.
final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/local-signup', builder: (context, state) => const LocalSignupScreen()),
    GoRoute(path: '/avatar', builder: (context, state) => AvatarPickerScreen(prefillName: (state.extra as Map<String, dynamic>?)?['name'] as String?)),
    GoRoute(path: '/set-home', builder: (context, state) => const SetHomeScreen()),

    ShellRoute(
      builder: (context, state, child) => HomeScreen(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => _noTransitionPage(const HomeTab(), state, 'home'),
        ),
        GoRoute(
          path: '/leaderboard',
          pageBuilder: (context, state) => _noTransitionPage(const LeaderboardScreen(), state, 'leaderboard'),
        ),
        GoRoute(
          path: '/achievements',
          pageBuilder: (context, state) => _noTransitionPage(const AchievementsScreen(), state, 'achievements'),
        ),
      ],
    ),

    GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),

    GoRoute(path: '/journey', builder: (context, state) => const JourneyScreen()),
    GoRoute(path: '/walk-history', builder: (context, state) => const WalkHistoryScreen()),
    GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
    GoRoute(
      path: '/user-profile',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return UserProfileScreen(
          userId: extra['userId'] as String,
          name: extra['name'] as String,
          avatarId: extra['avatar'] as int,
          color: extra['color'] as String,
          rank: extra['rank'] as int,
        );
      },
    ),
  ],
);