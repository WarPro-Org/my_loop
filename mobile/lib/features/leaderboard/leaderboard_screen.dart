/// Leaderboard screen — displays player rankings in a Duolingo-league style.
///
/// Shows a podium visualization for the top 3 players and a scrollable
/// list for remaining ranks. Powered by the `/api/leaderboard` endpoint.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/models/leaderboard_entry.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';
import 'package:myloop/shared/widgets/shimmer_loading.dart';

/// Riverpod provider that fetches leaderboard data from the API.
final leaderboardProvider = FutureProvider.autoDispose<List<LeaderboardEntry>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getLeaderboard(lat: 0, lng: 0);
});

/// ─────────────────────────────────────────────────────────────────────────────
/// LEADERBOARD SCREEN
/// ─────────────────────────────────────────────────────────────────────────────

/// The leaderboard tab showing local area rankings.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardProvider);
    final user = ref.watch(userProfileProvider);

    return Scaffold(
      body: SafeArea(
        child: leaderboard.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Center(child: ShimmerBox(width: 200, height: 28, borderRadius: 8)),
                const SizedBox(height: 8),
                Center(child: ShimmerBox(width: 120, height: 16, borderRadius: 6)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: ShimmerBox(height: 140)),
                    const SizedBox(width: 8),
                    Expanded(child: ShimmerBox(height: 180)),
                    const SizedBox(width: 8),
                    Expanded(child: ShimmerBox(height: 120)),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(child: ShimmerList(itemCount: 5, itemHeight: 56, padding: EdgeInsets.zero)),
              ],
            ),
          ),
          error: (err, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 48, color: AppColors.grey),
                const SizedBox(height: 12),
                Text('Could not load leaderboard', style: TextStyle(color: AppColors.grey)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(leaderboardProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (entries) => Column(
            children: [
              const SizedBox(height: 16),
              Text('🏆 Leaderboard', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Your area • Today',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.grey),
              ),
              const SizedBox(height: 16),
              if (entries.length >= 3) _TopThreePodium(top3: entries.sublist(0, 3)),
              const SizedBox(height: 16),
              Expanded(child: _RankingList(
                players: entries.length > 3 ? entries.sublist(3) : (entries.length < 3 ? entries : []),
                currentUserName: user.displayName,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// TOP 3 PODIUM
/// ─────────────────────────────────────────────────────────────────────────────

class _TopThreePodium extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  const _TopThreePodium({required this.top3});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _PodiumItem(entry: top3[1], height: 80)),
          const SizedBox(width: 8),
          Expanded(child: _PodiumItem(entry: top3[0], height: 100)),
          const SizedBox(width: 8),
          Expanded(child: _PodiumItem(entry: top3[2], height: 64)),
        ],
      ),
    );
  }
}

class _PodiumItem extends StatelessWidget {
  final LeaderboardEntry entry;
  final double height;
  const _PodiumItem({required this.entry, required this.height});

  @override
  Widget build(BuildContext context) {
    final medals = ['🥇', '🥈', '🥉'];
    return GestureDetector(
      onTap: () => context.push('/user-profile', extra: {
        'userId': entry.userId,
        'name': entry.displayName,
        'avatar': entry.avatarId,
        'color': entry.color,
        'rank': entry.rank,
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(medals[entry.rank - 1], style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 4),
          AvatarWidget(avatarId: entry.avatarId, color: entry.color, size: 44, hexes: entry.hexCount),
          const SizedBox(height: 4),
          Text(entry.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
          Text('${entry.cellCount} ⬡', style: TextStyle(fontSize: 11, color: AppColors.grey)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              color: entry.rank == 1 ? AppColors.yellow.withValues(alpha: 0.3)
                  : entry.rank == 2 ? AppColors.grey.withValues(alpha: 0.2)
                  : AppColors.orange.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// RANKING LIST
/// ─────────────────────────────────────────────────────────────────────────────

class _RankingList extends StatelessWidget {
  final List<LeaderboardEntry> players;
  final String currentUserName;
  const _RankingList({required this.players, required this.currentUserName});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: players.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.greyLight),
      itemBuilder: (context, index) {
        final p = players[index];
        final isMe = p.displayName == currentUserName;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isMe ? null : () => context.push('/user-profile', extra: {
            'userId': p.userId,
            'name': p.displayName,
            'avatar': p.avatarId,
            'color': p.color,
            'rank': p.rank,
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '#${p.rank}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isMe ? AppColors.primary : AppColors.grey,
                    ),
                  ),
                ),
                AvatarWidget(avatarId: p.avatarId, color: p.color, size: 36, hexes: p.hexCount),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isMe ? AppColors.primary : AppColors.dark,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Text('${p.cellCount} ⬡', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );
      },
    );
  }
}
