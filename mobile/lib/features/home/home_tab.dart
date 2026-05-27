/// Home tab — the main dashboard players see after login.
///
/// Displays a welcome header with avatar, a daily challenge card with
/// progress, quick-stat tiles (streak, hexes, rank) with drill-down
/// bottom sheets, and a rotating "pro tip" card for engagement.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';

/// Rotating gameplay tips shown once per session to educate new players.
const _proTips = [
  'Walk a closed loop to capture all hexes inside it!',
  'Longer loops = more territory captured at once.',
  'You can steal other players\' hexes by walking through them.',
  'Walk during off-peak hours to claim territory unopposed.',
  'The closer your loop closes, the cleaner your capture.',
  'Small daily walks add up — consistency beats one big walk.',
  'Check the leaderboard to see who\'s near your territory.',
  'Walking 200m is the minimum to register a claim.',
  'Hexagons near landmarks are highly contested!',
  'Your trail captures hexes even without closing a loop.',
  'Walk in new areas to expand faster than defending old ones.',
  'A 500m loop can capture 20-30 hexagons at once!',
  'Morning walks have better GPS accuracy in urban areas.',
  'You keep territory even if you don\'t walk — unless someone takes it.',
  'Team up with friends to dominate a neighborhood!',
];

/// ─────────────────────────────────────────────────────────────────────────────
/// HOME TAB — Main scrollable dashboard content
/// ─────────────────────────────────────────────────────────────────────────────

/// The primary home tab showing player greeting, daily challenge, stats, and tips.
///
/// Stateless because all data is currently mocked. When connected to the
/// backend, this will become a [ConsumerWidget] watching user state.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  /// Builds the vertically scrollable dashboard layout.
  @override
  Widget build(BuildContext context) {
    // Pick a random tip each time screen builds (simulates per-login)
    final tip = _proTips[Random().nextInt(_proTips.length)];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header
            Row(
              children: [
                const AvatarWidget(avatarId: 1, color: '#00D4AA', size: 48),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hey, Player! 👋',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'Ready to conquer today?',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Daily challenge card
            _DailyChallengeCard(),
            const SizedBox(height: 20),

            // Quick stats row (interactive)
            _QuickStats(),
            const SizedBox(height: 24),

            // Tip of the day
            _TipCard(tip: tip),
            const SizedBox(height: 80), // space for FAB
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// DAILY CHALLENGE CARD
/// ─────────────────────────────────────────────────────────────────────────────

/// A gradient card showing today's challenge with a progress bar.
///
/// Currently displays static mock data (2/5 hexes). Will be powered by
/// a daily challenge system from the backend.
class _DailyChallengeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🎯', style: TextStyle(fontSize: 28)),
              SizedBox(width: 8),
              Text(
                'Daily Challenge',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Capture 5 new hexagons today!',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: 0.4, // 2/5 done
              minHeight: 10,
              backgroundColor: AppColors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation(AppColors.white),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '2 / 5 hexes captured',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// QUICK STATS ROW
/// ─────────────────────────────────────────────────────────────────────────────

/// Row of tappable stat tiles that open detail bottom sheets.
///
/// Each tile shows an emoji, a value, and a label. Tapping reveals
/// historical data (streak history, hex history) or rank scope options.
class _QuickStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            emoji: '🔥',
            value: '5',
            label: 'Streak',
            onTap: () => _showStreakHistory(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            emoji: '⬡',
            value: '24',
            label: 'Hexes',
            onTap: () => _showHexHistory(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            emoji: '🏆',
            value: '#8',
            label: 'Rank',
            onTap: () => _showRankSelector(context),
          ),
        ),
      ],
    );
  }

  /// Opens a bottom sheet showing the daily streak history with
  /// per-day hex count, distance walked, and time spent.
  void _showStreakHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔥 Streak History', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            // Mock daily data
            ..._mockDays.map((day) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(day['date'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('⬡ ${day['hexes']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('📏 ${day['distance']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('⏱️ ${day['time']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  /// Opens a bottom sheet showing hex earned/lost per day.
  void _showHexHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⬡ Hex History', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            ..._mockDays.map((day) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(day['date'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    '+${day['earned']} earned',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '-${day['lost']} lost',
                    style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  /// Opens a bottom sheet showing rank at different geographic scopes.
  void _showRankSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🏆 Your Rank', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            _RankOption(scope: 'Neighborhood', rank: 3, emoji: '📍'),
            _RankOption(scope: 'City', rank: 8, emoji: '🏙️'),
            _RankOption(scope: 'Country', rank: 1247, emoji: '🌍'),
          ],
        ),
      ),
    );
  }

  static final _mockDays = [
    {'date': 'Today', 'hexes': 5, 'distance': '1.2 km', 'time': '18 min', 'earned': 5, 'lost': 1},
    {'date': 'May 26', 'hexes': 8, 'distance': '2.1 km', 'time': '32 min', 'earned': 8, 'lost': 0},
    {'date': 'May 25', 'hexes': 3, 'distance': '0.8 km', 'time': '12 min', 'earned': 3, 'lost': 2},
    {'date': 'May 24', 'hexes': 6, 'distance': '1.5 km', 'time': '24 min', 'earned': 6, 'lost': 0},
    {'date': 'May 23', 'hexes': 2, 'distance': '0.5 km', 'time': '8 min', 'earned': 2, 'lost': 3},
  ];
}

/// A geographic scope rank display row used in the rank bottom sheet.
class _RankOption extends StatelessWidget {
  final String scope;
  final int rank;
  final String emoji;
  const _RankOption({required this.scope, required this.rank, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.snow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyLight, width: 2),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Text(scope, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Spacer(),
          Text(
            '#$rank',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// A single tappable stat tile with emoji, value, and label.
///
/// Used in the [_QuickStats] row. The [onTap] callback opens the
/// corresponding detail bottom sheet.
class _MiniStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final VoidCallback onTap;
  const _MiniStat({required this.emoji, required this.value, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.greyLight, width: 2),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: AppColors.grey, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// TIP CARD
/// ─────────────────────────────────────────────────────────────────────────────

/// Displays a random gameplay tip with a lightbulb emoji.
///
/// The tip is randomly selected from [_proTips] each time the home tab rebuilds.
class _TipCard extends StatelessWidget {
  final String tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3), width: 2),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pro tip',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  tip,
                  style: TextStyle(fontSize: 13, color: AppColors.dark.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
