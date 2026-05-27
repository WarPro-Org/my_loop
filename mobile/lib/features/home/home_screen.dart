/// Home screen shell — the main navigation container for authenticated users.
///
/// Wraps the active tab content with a bottom navigation bar and a
/// floating "Start Journey" button. Uses GoRouter's nested navigation
/// to swap between Home, Leaderboard, and Profile tabs.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';

/// The app shell scaffold providing bottom navigation and the journey FAB.
///
/// Receives the active tab [child] from GoRouter's `ShellRoute`. The
/// bottom nav and FAB remain persistent across tab switches.
class HomeScreen extends StatelessWidget {
  /// The currently active tab widget injected by GoRouter.
  final Widget child;
  const HomeScreen({super.key, required this.child});

  /// Assembles the scaffold with body, bottom nav, and centered FAB.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _BottomNav(),
      floatingActionButton: _StartJourneyFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

/// The circular floating action button that launches the journey screen.
///
/// Positioned at the center of the bottom navigation bar via
/// [FloatingActionButtonLocation.centerDocked]. Navigates to `/journey`
/// using a push (not go) so the user can pop back.
class _StartJourneyFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.4),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => context.push('/journey'),
        backgroundColor: AppColors.primary,
        elevation: 0,
        shape: const CircleBorder(),
        child: const Icon(
          Icons.directions_walk,
          color: AppColors.white,
          size: 30,
        ),
      ),
    );
  }
}

/// Bottom navigation bar with emoji icons for Home, Ranks, and Profile.
///
/// Reads the current route from [GoRouterState] to determine the active tab
/// index, and uses `context.go()` to navigate between tabs.
class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    int currentIndex = 0;
    if (location == '/leaderboard') currentIndex = 1;
    if (location == '/profile') currentIndex = 2;

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            context.go('/home');
          case 1:
            context.go('/leaderboard');
          case 2:
            context.go('/profile');
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Text('🏠', style: TextStyle(fontSize: 22)),
          activeIcon: Text('🏠', style: TextStyle(fontSize: 26)),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Text('🏆', style: TextStyle(fontSize: 22)),
          activeIcon: Text('🏆', style: TextStyle(fontSize: 26)),
          label: 'Ranks',
        ),
        BottomNavigationBarItem(
          icon: Text('👤', style: TextStyle(fontSize: 22)),
          activeIcon: Text('👤', style: TextStyle(fontSize: 26)),
          label: 'Profile',
        ),
      ],
    );
  }
}
