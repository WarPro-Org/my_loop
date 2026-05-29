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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 28),

          // Profile header: avatar + name/tag side by side, centered
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar with glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(int.parse(widget.color.replaceFirst('#', ''), radix: 16) | 0xFF000000).withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: AvatarWidget(avatarId: widget.avatarId, color: widget.color, size: 52, hexes: hexCount),
              ),
              const SizedBox(width: 14),
              // Name + tag
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 19),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title.emoji, style: const TextStyle(fontSize: 12, height: 1.0)),
                        const SizedBox(width: 4),
                        Text(title.label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Badge centered
          HexTrophyBadge(hexes: hexCount, size: 64, showLabel: true, showProgress: true),
          const SizedBox(height: 24),

          // Streak row
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isStreakActive
                  ? [AppColors.orange.withValues(alpha: 0.12), AppColors.red.withValues(alpha: 0.06)]
                  : [AppColors.greyLight.withValues(alpha: 0.5), AppColors.greyLight.withValues(alpha: 0.3)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isStreakActive ? AppColors.orange.withValues(alpha: 0.3) : AppColors.greyLight),
            ),
            child: Row(
              children: [
                Text(isStreakActive ? '🔥' : '⏸️', style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isStreakActive ? '$streak-day streak!' : 'Streak paused',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isStreakActive ? AppColors.dark : AppColors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stats list — simple rows
          _StatRow(icon: Icons.hexagon, label: 'Hexes Owned', value: '$hexCount', color: AppColors.primary),
          _StatRow(icon: Icons.directions_walk, label: 'Distance Walked', value: '${distanceKm.toStringAsFixed(1)} km', color: AppColors.accent),
          _StatRow(icon: Icons.whatshot, label: 'Best Streak', value: '$maxStreak days', color: AppColors.orange),
          _StatRow(icon: Icons.emoji_events, label: 'Top 3 Finishes', value: '$topThree', color: AppColors.yellow),

          const SizedBox(height: 24),
          // Joined date at bottom center
          Text('Joined $joinLabel', style: TextStyle(color: AppColors.grey, fontSize: 12)),
          const SizedBox(height: 32),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.grey)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      ),
    );
  }
}
