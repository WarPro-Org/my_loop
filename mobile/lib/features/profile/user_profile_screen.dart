/// Public profile screen — shows another player's detailed stats from the API.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/models/player_titles.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';
import 'package:myloop/shared/widgets/hex_trophy.dart';
import 'package:myloop/shared/widgets/shimmer_loading.dart';

/// Displays another user's rich public profile fetched from the API.
class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  final String name;
  final int avatarId;
  final String color;
  final int rank;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.avatarId,
    required this.color,
    required this.rank,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getUserProfile(widget.userId);
      if (mounted) setState(() { _profile = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load profile'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
          ? _buildShimmer()
          : _error != null
            ? _buildError()
            : _buildProfile(),
      ),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          ShimmerBox(width: 96, height: 96, borderRadius: 48),
          const SizedBox(height: 16),
          ShimmerBox(width: 150, height: 24, borderRadius: 8),
          const SizedBox(height: 8),
          ShimmerBox(width: 80, height: 20, borderRadius: 8),
          const SizedBox(height: 32),
          ...List.generate(6, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ShimmerBox(height: 52, borderRadius: 12),
          )),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 48, color: AppColors.grey),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.grey)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () { setState(() { _loading = true; _error = null; }); _fetchProfile(); },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    final p = _profile!;
    final hexCount = (p['hexCount'] as num?)?.toInt() ?? 0;
    final streak = (p['streak'] as num?)?.toInt() ?? 0;
    final maxStreak = (p['maxStreak'] as num?)?.toInt() ?? 0;
    final distanceKm = (p['distanceKm'] as num?)?.toDouble() ?? 0.0;
    final topThree = (p['topThreeFinishes'] as num?)?.toInt() ?? 0;
    final isStreakActive = p['isStreakActive'] as bool? ?? false;
    final joinedAt = p['joinedAt'] as String?;
    final title = getTitleForHexes(hexCount);

    // Parse join date
    String joinLabel = 'Unknown';
    if (joinedAt != null) {
      final date = DateTime.tryParse(joinedAt);
      if (date != null) {
        final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        joinLabel = '${months[date.month - 1]} ${date.year}';
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Profile header card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.greyLight, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                // Avatar
                AvatarWidget(avatarId: widget.avatarId, color: widget.color, size: 52, hexes: hexCount),
                const SizedBox(width: 14),
                // Name + title + joined
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 20),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${title.emoji} ${title.label}',
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Joined $joinLabel',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Badge — properly centered with breathing room
                HexTrophyBadge(hexes: hexCount, size: 60, showLabel: true, showProgress: true),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Streak badge
          _StreakBadge(streak: streak, maxStreak: maxStreak, isActive: isStreakActive),
          const SizedBox(height: 20),

          // Stats
          _StatRow(icon: Icons.hexagon, label: 'Total Hexes', value: '$hexCount', color: AppColors.primary),
          _StatRow(icon: Icons.directions_walk, label: 'Distance', value: '${distanceKm.toStringAsFixed(1)} km', color: AppColors.accent),
          _StatRow(icon: Icons.whatshot, label: 'Max Streak', value: '$maxStreak days', color: AppColors.red),
          _StatRow(icon: Icons.emoji_events, label: 'Top 3 Finishes', value: '$topThree', color: AppColors.yellow),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final int streak;
  final int maxStreak;
  final bool isActive;
  const _StreakBadge({required this.streak, required this.maxStreak, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
            ? [AppColors.orange.withValues(alpha: 0.15), AppColors.red.withValues(alpha: 0.1)]
            : [AppColors.greyLight, AppColors.greyLight],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? AppColors.orange.withValues(alpha: 0.3) : AppColors.greyLight),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.local_fire_department : Icons.pause_circle_outline,
            color: isActive ? AppColors.orange : AppColors.grey,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'On a $streak-day streak!' : 'Streak paused',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isActive ? AppColors.dark : AppColors.grey,
                  ),
                ),
                Text(
                  'Best: $maxStreak days',
                  style: const TextStyle(fontSize: 13, color: AppColors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatRow({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.grey))),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
