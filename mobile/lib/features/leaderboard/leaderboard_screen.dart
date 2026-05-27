/// Leaderboard screen — displays player rankings in a Duolingo-league style.
///
/// Shows a podium visualization for the top 3 players and a scrollable
/// list for remaining ranks. Currently uses mock data; will be powered
/// by the `/api/leaderboard` endpoint.
library;

import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// LEADERBOARD SCREEN
/// ─────────────────────────────────────────────────────────────────────────────

/// The leaderboard tab showing local area rankings.
///
/// Layout: header with title and scope label, top-3 podium visualization,
/// then a scrollable list for ranks 4+. The current user's row is
/// highlighted with a tinted background.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  /// Builds the vertical layout: header → podium → ranking list.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Header
            Text('🏆 Leaderboard', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'Your area • Today',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.grey,
              ),
            ),
            const SizedBox(height: 16),

            // Top 3 podium
            _TopThreePodium(),
            const SizedBox(height: 16),

            // Rest of the list
            Expanded(child: _RankingList()),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// TOP 3 PODIUM
/// ─────────────────────────────────────────────────────────────────────────────

/// Podium visualization showing the top 3 players with medal emojis.
///
/// Arranged as: 2nd place (left) → 1st place (center, tallest) → 3rd place (right).
/// Each podium column height reflects the player's relative rank.
class _TopThreePodium extends StatelessWidget {
  // Mock data - will come from API later
  final _topPlayers = const [
    {'name': 'Alex', 'avatar': 0, 'color': '#00D4AA', 'cells': 142, 'rank': 1},
    {'name': 'Maya', 'avatar': 3, 'color': '#1CB0F6', 'cells': 98, 'rank': 2},
    {'name': 'Ravi', 'avatar': 5, 'color': '#FF9600', 'cells': 76, 'rank': 3},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd place
          _PodiumItem(
            rank: 2,
            name: _topPlayers[1]['name'] as String,
            avatarId: _topPlayers[1]['avatar'] as int,
            color: _topPlayers[1]['color'] as String,
            cells: _topPlayers[1]['cells'] as int,
            height: 80,
          ),
          const SizedBox(width: 8),
          // 1st place (tallest)
          _PodiumItem(
            rank: 1,
            name: _topPlayers[0]['name'] as String,
            avatarId: _topPlayers[0]['avatar'] as int,
            color: _topPlayers[0]['color'] as String,
            cells: _topPlayers[0]['cells'] as int,
            height: 100,
          ),
          const SizedBox(width: 8),
          // 3rd place
          _PodiumItem(
            rank: 3,
            name: _topPlayers[2]['name'] as String,
            avatarId: _topPlayers[2]['avatar'] as int,
            color: _topPlayers[2]['color'] as String,
            cells: _topPlayers[2]['cells'] as int,
            height: 64,
          ),
        ],
      ),
    );
  }
}

/// A single podium column: medal emoji, avatar, name, hex count, and colored bar.
class _PodiumItem extends StatelessWidget {
  final int rank;
  final String name;
  final int avatarId;
  final String color;
  final int cells;
  final double height;

  const _PodiumItem({
    required this.rank,
    required this.name,
    required this.avatarId,
    required this.color,
    required this.cells,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final medals = ['🥇', '🥈', '🥉'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(medals[rank - 1], style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        AvatarWidget(avatarId: avatarId, color: color, size: 44),
        const SizedBox(height: 4),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text('$cells ⬡', style: TextStyle(fontSize: 11, color: AppColors.grey)),
        const SizedBox(height: 4),
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            color: rank == 1 ? AppColors.yellow.withValues(alpha: 0.3)
                : rank == 2 ? AppColors.grey.withValues(alpha: 0.2)
                : AppColors.orange.withValues(alpha: 0.2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// RANKING LIST
/// ─────────────────────────────────────────────────────────────────────────────

/// Scrollable list of players ranked 4th and below.
///
/// Highlights the current user's row with a tinted primary-color background.
/// Each row shows rank number, avatar, name, and hex count.
class _RankingList extends StatelessWidget {
  // Mock data
  final _players = const [
    {'name': 'Sam', 'avatar': 2, 'color': '#A560E8', 'cells': 54, 'rank': 4},
    {'name': 'Priya', 'avatar': 8, 'color': '#FF4B4B', 'cells': 42, 'rank': 5},
    {'name': 'Leo', 'avatar': 4, 'color': '#FFC800', 'cells': 38, 'rank': 6},
    {'name': 'Zara', 'avatar': 6, 'color': '#2ED8A3', 'cells': 31, 'rank': 7},
    {'name': 'You', 'avatar': 1, 'color': '#00D4AA', 'cells': 24, 'rank': 8},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _players.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.greyLight),
      itemBuilder: (context, index) {
        final p = _players[index];
        final isMe = p['name'] == 'You';

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: isMe ? AppColors.primary.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Rank number
              SizedBox(
                width: 28,
                child: Text(
                  '#${p['rank']}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isMe ? AppColors.primary : AppColors.grey,
                  ),
                ),
              ),
              // Avatar
              AvatarWidget(
                avatarId: p['avatar'] as int,
                color: p['color'] as String,
                size: 36,
              ),
              const SizedBox(width: 12),
              // Name
              Expanded(
                child: Text(
                  p['name'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isMe ? AppColors.primary : AppColors.dark,
                  ),
                ),
              ),
              // Hex count
              Text(
                '${p['cells']} ⬡',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      },
    );
  }
}
