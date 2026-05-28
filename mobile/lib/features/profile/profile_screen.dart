/// Profile screen - displays player identity, stats, and settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';

/// The player's profile screen with identity, stats, and settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              AvatarWidget(avatarId: profile.avatarId, color: profile.color, size: 80),
              const SizedBox(height: 12),
              Text(profile.displayName, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 32),
              _SettingsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _SettingsTile(icon: Icons.palette, label: 'Change Avatar & Color', onTap: () => _showAvatarColorPicker(context, ref)),
        _SettingsTile(icon: Icons.edit, label: 'Edit Display Name', onTap: () => _showNameEditor(context, ref)),
        _SettingsTile(icon: Icons.logout, label: 'Sign Out', onTap: () => context.go('/login')),
      ],
    );
  }

  void _showAvatarColorPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _AvatarColorEditor(ref: ref),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name updated!'), backgroundColor: AppColors.primary),
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

class _AvatarColorEditor extends StatefulWidget {
  final WidgetRef ref;
  const _AvatarColorEditor({required this.ref});

  @override
  State<_AvatarColorEditor> createState() => _AvatarColorEditorState();
}

class _AvatarColorEditorState extends State<_AvatarColorEditor> {
  late int _selectedAvatar;
  late int _selectedColor;

  static const _colors = ['#00D4AA', '#1CB0F6', '#FF4B4B', '#FF9600', '#A560E8', '#FFC800', '#FF6B81', '#2ED8A3'];

  @override
  void initState() {
    super.initState();
    final profile = widget.ref.read(userProfileProvider);
    _selectedAvatar = profile.avatarId;
    final idx = _colors.indexOf(profile.color);
    _selectedColor = idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change Avatar & Color', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Center(child: AvatarWidget(avatarId: _selectedAvatar, color: _colors[_selectedColor], size: 72)),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: avatarEmojis.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedAvatar == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatar = index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.snow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? AppColors.primary : AppColors.greyLight, width: isSelected ? 2 : 1),
                    ),
                    child: Center(child: Text(avatarEmojis[index], style: const TextStyle(fontSize: 22))),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_colors.length, (index) {
              final color = Color(int.parse(_colors[index].replaceFirst('#', ''), radix: 16) | 0xFF000000);
              final isSelected = _selectedColor == index;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = index),
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? AppColors.darkHard : Colors.transparent, width: 3),
                  ),
                  child: isSelected ? const Icon(Icons.check, color: AppColors.white, size: 16) : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.ref.read(userProfileProvider.notifier).updateAvatarAndColor(_selectedAvatar, _colors[_selectedColor]);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Avatar updated!'), backgroundColor: AppColors.primary),
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
  final IconData icon;
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
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Icon(icon, color: AppColors.dark),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.grey),
          onTap: onTap,
        ),
      ),
    );
  }
}