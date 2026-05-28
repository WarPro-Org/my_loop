/// Avatar picker screen — post-signup player customization.
///
/// Allows new users to choose a display name, select an avatar emoji,
/// and pick a player color before entering the main app. This data is
/// sent to the backend to create their player profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/auth_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';
import 'package:myloop/shared/widgets/big_button.dart';

/// Screen where new players create their in-game identity.
///
/// Presents a name input, an emoji avatar grid, a color picker row, and
/// a live preview of the combined avatar. On completion, registers the
/// user via the API and navigates to the home screen.
class AvatarPickerScreen extends ConsumerStatefulWidget {
  const AvatarPickerScreen({super.key});

  @override
  ConsumerState<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

/// State for [AvatarPickerScreen] managing avatar, color, and name selection.
class _AvatarPickerScreenState extends ConsumerState<AvatarPickerScreen> {
  int _selectedAvatar = 0;
  int _selectedColor = 0;
  String _name = '';

  /// The 8 hex color options players can choose from for their avatar ring.
  static const _colors = [
    '#00D4AA', // green
    '#1CB0F6', // blue
    '#FF4B4B', // red
    '#FF9600', // orange
    '#A560E8', // purple
    '#FFC800', // yellow
    '#FF6B81', // pink
    '#2ED8A3', // teal
  ];

  /// Builds the scrollable form layout with name, avatar grid, colors, and CTA.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // Title
              Text(
                'Create your player! 🎮',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),

              // Name input
              TextField(
                onChanged: (v) => setState(() => _name = v),
                decoration: InputDecoration(
                  hintText: 'Your display name',
                  prefixIcon: const Icon(Icons.person),
                  filled: true,
                  fillColor: AppColors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.greyLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.greyLight, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Avatar label
              Text(
                'Pick your character',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              // Avatar grid
              SizedBox(
                height: 180,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: avatarEmojis.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedAvatar == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAvatar = index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.greyLight,
                            width: isSelected ? 3 : 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            avatarEmojis[index],
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Color label
              Text(
                'Pick your color',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              // Color picker row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_colors.length, (index) {
                  final color = Color(
                    int.parse(_colors[index].replaceFirst('#', ''), radix: 16) |
                        0xFF000000,
                  );
                  final isSelected = _selectedColor == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = index),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.darkHard : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: AppColors.white, size: 18)
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),

              // Preview
              Center(
                child: AvatarWidget(
                  avatarId: _selectedAvatar,
                  color: _colors[_selectedColor],
                  size: 64,
                ),
              ),

              const Spacer(),

              // Continue button
              BigButton(
                label: "LET'S GO! 🚀",
                onPressed: _name.trim().isEmpty
                    ? () {} // disabled look handled by opacity below
                    : () => _registerAndContinue(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _registerAndContinue() async {
    final name = _name.trim();
    final color = _colors[_selectedColor];
    final authService = ref.read(authServiceProvider);
    final api = ref.read(apiServiceProvider);

    // Use Firebase UID if available, otherwise generate a dev UID
    final firebaseUid = authService.currentUser?.uid ?? 'dev_${name.toLowerCase().replaceAll(' ', '_')}';

    try {
      final user = await api.register(
        firebaseUid: firebaseUid,
        displayName: name,
        color: color,
        avatarId: _selectedAvatar,
      );

      ref.read(userProfileProvider.notifier).setFromApi(
        userId: user.id,
        avatarId: user.avatarId,
        color: user.color,
        displayName: user.displayName,
        hexCount: user.hexCount,
        streak: user.streak,
        distanceKm: user.distanceKm,
      );

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }
}
