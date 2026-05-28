/// Home screen shell - main navigation container for authenticated users.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';

/// Global key so child widgets (like home_tab) can open the end drawer.
final homeScaffoldKey = GlobalKey<ScaffoldState>();

/// The app shell scaffold providing bottom navigation and the journey FAB (home only).
class HomeScreen extends ConsumerWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final isHome = location == '/home';

    return Scaffold(
      key: homeScaffoldKey,
      body: child,
      endDrawer: const _ProfileDrawer(),
      floatingActionButton: isHome
        ? _StartJourneyFab()
        : const SizedBox.shrink(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButtonAnimator: _NoAnimationFabAnimator(),
      bottomNavigationBar: _BottomNav(),
    );
  }
}

/// Sidebar drawer for profile settings (no stats — those stay on homepage).
class _ProfileDrawer extends ConsumerWidget {
  const _ProfileDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            AvatarWidget(avatarId: profile.avatarId, color: profile.color, size: 72),
            const SizedBox(height: 12),
            Text(profile.displayName, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Explorer', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.grey)),
            const SizedBox(height: 32),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _DrawerTile(icon: Icons.palette, label: 'Change Avatar & Color', onTap: () {
              Navigator.pop(context);
              context.push('/profile');
            }),
            _DrawerTile(icon: Icons.edit, label: 'Edit Display Name', onTap: () {
              Navigator.pop(context);
              _showNameEditor(context, ref);
            }),
            const Spacer(),
            const Divider(height: 1),
            _DrawerTile(icon: Icons.logout, label: 'Sign Out', onTap: () {
              Navigator.pop(context);
              context.go('/login');
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showNameEditor(BuildContext context, WidgetRef ref) {
    final profile = ref.read(userProfileProvider);
    final controller = TextEditingController(text: profile.displayName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Display Name', style: Theme.of(ctx).textTheme.headlineMedium),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter your name',
                filled: true,
                fillColor: AppColors.snow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.greyLight)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    ref.read(userProfileProvider.notifier).updateDisplayName(name);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('SAVE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.dark),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.grey, size: 20),
      onTap: onTap,
    );
  }
}

/// Disables the default FAB scale+fade animation.
class _NoAnimationFabAnimator extends FloatingActionButtonAnimator {
  @override
  Offset getOffset({required Offset begin, required Offset end, required double progress}) {
    return end;
  }

  @override
  Animation<double> getScaleAnimation({required Animation<double> parent}) {
    return const AlwaysStoppedAnimation(1.0);
  }

  @override
  Animation<double> getRotationAnimation({required Animation<double> parent}) {
    return const AlwaysStoppedAnimation(0.0);
  }
}

/// Attractive animated FAB that launches the journey screen.
class _StartJourneyFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/journey'),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.5),
              offset: const Offset(0, 6),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hexagon, color: AppColors.white, size: 28),
            const SizedBox(width: 10),
            const Text(
              'Start Journey',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom navigation bar: Home, Ranks, Achievements.
class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    int currentIndex = 0;
    if (location == '/leaderboard') currentIndex = 1;
    if (location == '/achievements') currentIndex = 2;

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            context.go('/home');
          case 1:
            context.go('/leaderboard');
          case 2:
            context.go('/achievements');
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined, size: 24),
          activeIcon: Icon(Icons.home, size: 28),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.leaderboard_outlined, size: 24),
          activeIcon: Icon(Icons.leaderboard, size: 28),
          label: 'Ranks',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.emoji_events_outlined, size: 24),
          activeIcon: Icon(Icons.emoji_events, size: 28),
          label: 'Achievements',
        ),
      ],
    );
  }
}