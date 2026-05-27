import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/models/achievements.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';

// Profile screen - shows player stats, avatar, and settings
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Avatar and name
              const AvatarWidget(avatarId: 1, color: '#58CC02', size: 80),
              const SizedBox(height: 12),
              Text('Player', style: Theme.of(context).textTheme.headlineMedium),
              Text(
                '🌍 Explorer since May 2026',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.grey,
                ),
              ),
              const SizedBox(height: 32),

              // Stats cards
              _StatsGrid(),
              const SizedBox(height: 24),

              // Achievements section
              _AchievementsSection(),
              const SizedBox(height: 24),

              // Settings
              _SettingsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// Grid of stat cards
class _StatsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: const [
        _StatCard(emoji: '⬡', value: '24', label: 'Hexes Owned'),
        _StatCard(emoji: '📏', value: '3.2 km', label: 'Total Walked'),
        _StatCard(emoji: '🏆', value: '#8', label: 'Local Rank'),
        _StatCard(emoji: '🔥', value: '5', label: 'Day Streak'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _StatCard({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greyLight, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// Achievements section - shows first few + "See All" button
class _AchievementsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Mock progress for some achievements
    final mockProgress = {
      'hex_1': 24, 'walk_1': 12, 'walk_2': 3, 'walk_3': 5,
      'hex_4': 8, 'social_3': 2, 'mile_1': 7, 'explore_1': 4,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Achievements 🎖️', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => _showAllAchievements(context, mockProgress),
              child: const Text('See All', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Show first 4 achievements
        ...achievements.take(4).map((a) => _AchievementTile(
          achievement: a,
          progress: mockProgress[a.id] ?? 0,
        )),
      ],
    );
  }

  void _showAllAchievements(BuildContext context, Map<String, int> progress) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _AllAchievementsScreen(progress: progress),
      ),
    );
  }
}

// Single achievement tile with stars
class _AchievementTile extends StatelessWidget {
  final Achievement achievement;
  final int progress;
  const _AchievementTile({required this.achievement, required this.progress});

  @override
  Widget build(BuildContext context) {
    final stars = achievement.getStars(progress);
    final nextTarget = stars == 0 ? achievement.tier1
        : stars == 1 ? achievement.tier2
        : stars == 2 ? achievement.tier3
        : achievement.tier3;
    final progressRatio = (progress / nextTarget).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyLight, width: 2),
      ),
      child: Row(
        children: [
          // Emoji
          Text(achievement.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          // Name + progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(achievement.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '$progress / $nextTarget ${achievement.unit}',
                  style: TextStyle(fontSize: 11, color: AppColors.grey),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    minHeight: 6,
                    backgroundColor: AppColors.greyLight,
                    valueColor: AlwaysStoppedAnimation(
                      stars >= 3 ? AppColors.yellow : AppColors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Stars
          Row(
            children: List.generate(3, (i) => Text(
              i < stars ? '⭐' : '☆',
              style: TextStyle(fontSize: i < stars ? 16 : 14),
            )),
          ),
        ],
      ),
    );
  }
}

// Full achievements screen
class _AllAchievementsScreen extends StatelessWidget {
  final Map<String, int> progress;
  const _AllAchievementsScreen({required this.progress});

  @override
  Widget build(BuildContext context) {
    final totalStars = achievements.fold<int>(
      0, (sum, a) => sum + a.getStars(progress[a.id] ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Achievements 🎖️'),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Star count header
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.yellow.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('⭐', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(
                  '$totalStars / ${achievements.length * 3} stars',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: achievements.length,
              itemBuilder: (context, index) => _AchievementTile(
                achievement: achievements[index],
                progress: progress[achievements[index].id] ?? 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Settings section with working buttons
class _SettingsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settings ⚙️', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _SettingsTile(
          icon: '🎨',
          label: 'Change Avatar & Color',
          onTap: () => _showAvatarColorPicker(context),
        ),
        _SettingsTile(
          icon: '📝',
          label: 'Edit Display Name',
          onTap: () => _showNameEditor(context),
        ),
        _SettingsTile(
          icon: '🚪',
          label: 'Sign Out',
          onTap: () => context.go('/login'),
        ),
      ],
    );
  }

  void _showAvatarColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _AvatarColorEditor(),
    );
  }

  void _showNameEditor(BuildContext context) {
    final controller = TextEditingController(text: 'Player');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Display Name 📝', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter your name',
                filled: true,
                fillColor: AppColors.snow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.greyLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.green, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Save name via API
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name updated! ✅'), backgroundColor: AppColors.green),
                  );
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

// Avatar and color editor bottom sheet
class _AvatarColorEditor extends StatefulWidget {
  const _AvatarColorEditor();

  @override
  State<_AvatarColorEditor> createState() => _AvatarColorEditorState();
}

class _AvatarColorEditorState extends State<_AvatarColorEditor> {
  int _selectedAvatar = 1;
  int _selectedColor = 0;

  static const _colors = [
    '#58CC02', '#1CB0F6', '#FF4B4B', '#FF9600',
    '#A560E8', '#FFC800', '#FF6B81', '#2ED8A3',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change Avatar & Color 🎨', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),

          // Preview
          Center(
            child: AvatarWidget(
              avatarId: _selectedAvatar,
              color: _colors[_selectedColor],
              size: 72,
            ),
          ),
          const SizedBox(height: 20),

          // Avatar grid
          SizedBox(
            height: 140,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: avatarEmojis.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedAvatar == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatar = index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.green.withValues(alpha: 0.15) : AppColors.snow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppColors.green : AppColors.greyLight,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(child: Text(avatarEmojis[index], style: const TextStyle(fontSize: 22))),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Color row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_colors.length, (index) {
              final color = Color(int.parse(_colors[index].replaceFirst('#', ''), radix: 16) | 0xFF000000);
              final isSelected = _selectedColor == index;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = index),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.darkHard : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: isSelected ? const Icon(Icons.check, color: AppColors.white, size: 16) : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // TODO: Save via API
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Avatar updated! ✅'), backgroundColor: AppColors.green),
                );
              },
              child: const Text('SAVE CHANGES'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyLight, width: 2),
      ),
      child: ListTile(
        leading: Text(icon, style: const TextStyle(fontSize: 20)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.grey),
        onTap: onTap,
      ),
    );
  }
}
