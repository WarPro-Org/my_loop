import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';

// Home screen - shell with bottom navigation
// Shows: Start Journey button (main CTA) + bottom nav for Leaderboard & Profile
class HomeScreen extends StatelessWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

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

// The floating "Start Journey" button in the middle of bottom nav
class _StartJourneyFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.green,
        boxShadow: [
          BoxShadow(
            color: AppColors.greenDark.withValues(alpha: 0.4),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => context.push('/journey'),
        backgroundColor: AppColors.green,
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

// Bottom navigation bar
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
