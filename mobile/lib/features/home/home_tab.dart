/// Home tab — the main dashboard players see after login.
///
/// Displays a welcome header with avatar, a daily challenge card with
/// progress, quick-stat tiles (streak, hexes, rank) with drill-down
/// bottom sheets, a Reels-style horizontal info carousel, and a rotating
/// "pro tip" card for engagement. Shows shimmer loading on initial load.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/features/home/home_screen.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/animated_hexagon.dart';
import 'package:myloop/shared/widgets/avatar_widget.dart';
import 'package:myloop/shared/widgets/hex_trophy.dart';
import 'package:myloop/shared/widgets/shimmer_loading.dart';

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

/// Whether the home tab has finished its initial shimmer loading.
final homeTabLoadedProvider = NotifierProvider<_HomeTabLoadedNotifier, bool>(_HomeTabLoadedNotifier.new);

class _HomeTabLoadedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void markLoaded() => state = true;
  void markLoading() => state = false;
}

/// The primary home tab showing player greeting, daily challenge, stats, and tips.
///
/// Shows shimmer placeholders briefly while data loads, then reveals content.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _isLoading = false);
        ref.read(homeTabLoadedProvider.notifier).markLoaded();
      }
    });
  }

  /// Builds the vertically scrollable dashboard layout.
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShimmerBox(width: 48, height: 48, borderRadius: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(height: 20, width: 160, borderRadius: 6),
                      const SizedBox(height: 8),
                      ShimmerBox(height: 14, width: 120, borderRadius: 6),
                    ],
                  )),
                ],
              ),
              const SizedBox(height: 32),
              ShimmerBox(height: 160),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: ShimmerBox(height: 80)),
                const SizedBox(width: 12),
                Expanded(child: ShimmerBox(height: 80)),
                const SizedBox(width: 12),
                Expanded(child: ShimmerBox(height: 80)),
              ]),
              const SizedBox(height: 24),
              ShimmerBox(height: 72),
            ],
          ),
        ),
      );
    }

    // Stable tip: rotate daily rather than on every rebuild
    final dayIndex = DateTime.now().day % _proTips.length;
    final tip = _proTips[dayIndex];
    final profile = ref.watch(userProfileProvider);
    final myHexes = profile.hexCount;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: animated hex mascot + greeting + avatar settings button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated hex mascot — same size as avatar button
                const AnimatedHexagon(size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hey, ${profile.displayName}! 👋',
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
                ),
                // Settings button = user's hex avatar badge — made to look tappable
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => homeScaffoldKey.currentState?.openEndDrawer(),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: AvatarWidget(
                          avatarId: profile.avatarId,
                          color: profile.color,
                          size: 48,
                          hexes: myHexes,
                        ),
                      ),
                      // Small badge indicator
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.white, width: 2),
                          ),
                          child: const Icon(Icons.menu, size: 10, color: AppColors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Daily challenge card
            _DailyChallengeCard(),
            const SizedBox(height: 20),

            // Quick stats row (interactive)
            _QuickStats(),
            const SizedBox(height: 24),

            // Reels-style info carousel
            _InfoReels(),
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
              Expanded(
                child: Text(
                  'Daily Challenge',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
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
class _QuickStats extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProfileProvider);
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            emoji: '🔥',
            value: '${user.streak}',
            label: 'Streak',
            onTap: () => _showStreakHistory(context, user),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            emoji: '⬡',
            value: '${user.hexCount}',
            label: 'Hexes',
            onTap: () => _showHexHistory(context, user),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            emoji: '🏆',
            value: '#${user.rank}',
            label: 'Rank',
            onTap: () => _showRankSelector(context, ref),
          ),
        ),
      ],
    );
  }

  /// Opens a bottom sheet showing the daily streak history.
  void _showStreakHistory(BuildContext context, UserProfile user) {
    final currentStreak = user.streak;
    final streakBroken = currentStreak == 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              // Streak hero - normal or broken state
              if (streakBroken) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF636E72), Color(0xFF2D3436)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const _SadHexFace(size: 52),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Streak Lost!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('Walk today to start a new one', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFA502), Color(0xFFFF6348)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 48)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$currentStreak Day Streak', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('Keep walking daily!', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text('Daily History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Expanded(
                child: _StreakHistoryLazy(scroll: scroll),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens a bottom sheet showing hex earned/lost per day + tier scale.
  void _showHexHistory(BuildContext context, UserProfile user) {
    final userHexes = user.hexCount;
    final tier = HexTier.fromHexes(userHexes);
    final division = HexTier.divisionFromHexes(userHexes);
    final divLabel = HexTier.fullLabel(userHexes);
    // Calculate next milestone (next division or next tier)
    final nextTier = tier.next;
    final tierRange = nextTier != null ? (nextTier.threshold - tier.threshold).toDouble() : 5000.0;
    final divSize = tierRange / 4;
    final nextDivThreshold = (tier.threshold + division * divSize).round();
    final toNextDiv = nextDivThreshold - userHexes;
    const romans = ['I', 'II', 'III', 'IV'];
    final nextLabel = division < 4
        ? '${tier.label} ${romans[division]}'  // next division in same tier
        : (nextTier?.label ?? 'Max');           // next tier

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              // Trophy hero
              Row(
                children: [
                  HexTrophyBadge(hexes: userHexes, size: 64, showProgress: false, showLabel: false),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$userHexes Hexes', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                        Text(divLabel, style: TextStyle(color: tier.color, fontWeight: FontWeight.w700, fontSize: 14)),
                        if (toNextDiv > 0) Text('$toNextDiv more for $nextLabel', style: TextStyle(color: AppColors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Division progress
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: HexTier.divisionProgress(userHexes),
                  minHeight: 10,
                  backgroundColor: tier.color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(tier.color),
                ),
              ),
              const SizedBox(height: 20),
              // Full tier scale
              Text('All Tiers', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              HexTierShowcase(currentHexes: userHexes),
              const SizedBox(height: 20),
              Text('Hex History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Expanded(
                child: _HexHistoryLazy(scroll: scroll),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens a bottom sheet showing rank at different geographic scopes.
  void _showRankSelector(BuildContext context, WidgetRef ref) {
    final user = ref.read(userProfileProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _RankSheet(cityRank: user.rank, userId: user.userId),
    );
  }
}

/// Bottom sheet that fetches and displays rank across all scopes.
class _RankSheet extends StatefulWidget {
  final int cityRank;
  final String? userId;
  const _RankSheet({required this.cityRank, this.userId});

  @override
  State<_RankSheet> createState() => _RankSheetState();
}

class _RankSheetState extends State<_RankSheet> {
  int _countryRank = 0;
  int _worldRank = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRanks();
  }

  Future<void> _fetchRanks() async {
    if (widget.userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final container = ProviderScope.containerOf(context);
      final api = container.read(apiServiceProvider);
      final results = await Future.wait([
        api.getLeaderboard(lat: 0, lng: 0, userId: widget.userId, scope: 'country'),
        api.getLeaderboard(lat: 0, lng: 0, userId: widget.userId, scope: 'world'),
      ]);
      if (mounted) {
        setState(() {
          _countryRank = results[0].myRank ?? 0;
          _worldRank = results[1].myRank ?? 0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rank = widget.cityRank > 0 ? widget.cityRank : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          // Rank hero card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFD93D), Color(0xFFF59E0B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 44)),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('#$rank in Your City', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(rank <= 3 && rank > 0 ? 'Podium finish! 🥇' : 'Keep walking to climb!', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Your Ranking', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _RankOption(scope: 'City', rank: rank, emoji: '🏙️'),
          _RankOption(scope: 'Country', rank: _loading ? -1 : _countryRank, emoji: '🌍'),
          _RankOption(scope: 'World', rank: _loading ? -1 : _worldRank, emoji: '🌐'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A geographic scope rank display row used in the rank bottom sheet.
class _RankOption extends StatelessWidget {
  final String scope;
  final int rank; // -1 = loading, 0 = unknown
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
          Expanded(
            child: Text(scope, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          rank == -1
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(
                  rank > 0 ? '#$rank' : '—',
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

/// ─────────────────────────────────────────────────────────────────────────────
/// INFO REELS — Instagram-style horizontal scrollable cards
/// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal carousel of engaging hook cards — designed to hook users like YouTube/TikTok.
/// Big bold text, urgency hooks, vibrant gradients, auto-scrolling.
class _InfoReels extends StatefulWidget {
  @override
  State<_InfoReels> createState() => _InfoReelsState();
}

class _InfoReelsState extends State<_InfoReels> {
  final _controller = PageController(viewportFraction: 0.85);
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _reels = [
    _ReelData(
      emoji: '🔥',
      title: '5 hexes away from Bronze II!',
      body: 'Just one short walk and you level up. Don\'t let someone steal your spot!',
      gradient: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
      hook: 'LEVEL UP TODAY',
    ),
    _ReelData(
      emoji: '⚡',
      title: 'Kai just captured 12 hexes!',
      body: 'Top player is on the move. Walk now to protect your territory!',
      gradient: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
      hook: 'DEFEND NOW',
    ),
    _ReelData(
      emoji: '🗺️',
      title: '47 unclaimed hexes nearby',
      body: 'Free territory waiting! Be the first to walk there and claim them all.',
      gradient: [Color(0xFF00D4AA), Color(0xFF00897B)],
      hook: 'GRAB FREE HEXES',
    ),
    _ReelData(
      emoji: '🏆',
      title: 'You\'re rank #8 — catch Leo!',
      body: 'Only 106 hexes behind! One good loop walk and you overtake them.',
      gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
      hook: 'CLIMB RANKS',
    ),
    _ReelData(
      emoji: '💎',
      title: '4 divisions to Silver tier',
      body: 'Keep your streak alive! Daily walks compound fast toward Silver.',
      gradient: [Color(0xFF60A5FA), Color(0xFF2563EB)],
      hook: 'TIER UP',
    ),
    _ReelData(
      emoji: '⚔️',
      title: 'Ravi stole 3 of your hexes!',
      body: 'Walk through their territory to steal them back. Revenge time!',
      gradient: [Color(0xFFE17055), Color(0xFFB33B27)],
      hook: 'FIGHT BACK',
    ),
    _ReelData(
      emoji: '🎯',
      title: 'Close a loop for 10x hexes!',
      body: 'Walking a closed loop captures every hex inside. Bigger loop = more territory.',
      gradient: [Color(0xFF0984E3), Color(0xFF0652DD)],
      hook: 'PRO TIP',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              const AnimatedHexagon(size: 28),
              const SizedBox(width: 8),
              Text('What\'s Happening', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _controller,
            itemCount: _reels.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _ReelCard(data: _reels[index]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Page indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_reels.length, (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _currentPage ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _currentPage ? AppColors.primary : AppColors.greyLight,
              borderRadius: BorderRadius.circular(3),
            ),
          )),
        ),
      ],
    );
  }
}

/// Data model for a single reel card.
class _ReelData {
  final String emoji;
  final String title;
  final String body;
  final List<Color> gradient;
  final String hook;
  const _ReelData({required this.emoji, required this.title, required this.body, required this.gradient, required this.hook});
}

/// A single reel card — gradient background with hook badge, emoji, title, and CTA.
class _ReelCard extends StatelessWidget {
  final _ReelData data;
  const _ReelCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: data.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: data.gradient[0].withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hook badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              data.hook,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(data.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.2),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              data.body,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, height: 1.3),
              maxLines: 3, overflow: TextOverflow.ellipsis,
            ),
          ),
          // CTA arrow
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// SAD HEX FACE (streak broken)
/// ─────────────────────────────────────────────────────────────────────────────

/// A sad hexagon face with big crying eyes — shows when streak is lost.
class _SadHexFace extends StatefulWidget {
  final double size;
  const _SadHexFace({this.size = 48});

  @override
  State<_SadHexFace> createState() => _SadHexFaceState();
}

class _SadHexFaceState extends State<_SadHexFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _SadHexPainter(wobble: _ctrl.value)),
      ),
    );
  }
}

class _SadHexPainter extends CustomPainter {
  final double wobble;
  _SadHexPainter({required this.wobble});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.44;
    canvas.save();
    canvas.translate(cx, cy);

    // Hex body (grey)
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final a = (math.pi / 3) * i - math.pi / 2;
      if (i == 0) {
        path.moveTo(r * math.cos(a), r * math.sin(a));
      } else {
        path.lineTo(r * math.cos(a), r * math.sin(a));
      }
    }
    path.close();
    canvas.drawPath(path, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF636E72), Color(0xFF2D3436)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)));

    // Eyes (big, sad)
    final eyeY = -r * 0.15 + wobble * 2;
    canvas.drawOval(Rect.fromCenter(center: Offset(-r * 0.25, eyeY), width: r * 0.25, height: r * 0.3),
      Paint()..color = Colors.white);
    canvas.drawCircle(Offset(-r * 0.25, eyeY + r * 0.04), r * 0.08, Paint()..color = const Color(0xFF2D3436));
    canvas.drawOval(Rect.fromCenter(center: Offset(r * 0.25, eyeY), width: r * 0.25, height: r * 0.3),
      Paint()..color = Colors.white);
    canvas.drawCircle(Offset(r * 0.25, eyeY + r * 0.04), r * 0.08, Paint()..color = const Color(0xFF2D3436));

    // Sad mouth (frown)
    canvas.drawArc(Rect.fromCenter(center: Offset(0, r * 0.35), width: r * 0.5, height: r * 0.3),
      math.pi * 0.1, math.pi * 0.8, false,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round);

    // Tear drops
    final tearY = eyeY + r * 0.2 + wobble * 4;
    canvas.drawCircle(Offset(-r * 0.28, tearY), r * 0.05, Paint()..color = const Color(0xFF74B9FF));
    canvas.drawCircle(Offset(r * 0.3, tearY + 2), r * 0.04, Paint()..color = const Color(0xFF74B9FF));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SadHexPainter old) => wobble != old.wobble;
}

/// ─────────────────────────────────────────────────────────────────────────────
/// HEX HISTORY LAZY (shows top 5 then loads more)
/// ─────────────────────────────────────────────────────────────────────────────

class _HexHistoryLazy extends StatefulWidget {
  final ScrollController scroll;
  const _HexHistoryLazy({required this.scroll});

  @override
  State<_HexHistoryLazy> createState() => _HexHistoryLazyState();
}

class _HexHistoryLazyState extends State<_HexHistoryLazy> {
  static final _allDays = [
    {'date': 'Today', 'earned': 5, 'lost': 1},
    {'date': 'May 26', 'earned': 8, 'lost': 0},
    {'date': 'May 25', 'earned': 3, 'lost': 2},
    {'date': 'May 24', 'earned': 6, 'lost': 0},
    {'date': 'May 23', 'earned': 2, 'lost': 3},
    {'date': 'May 22', 'earned': 4, 'lost': 1},
    {'date': 'May 21', 'earned': 7, 'lost': 0},
    {'date': 'May 20', 'earned': 3, 'lost': 2},
    {'date': 'May 19', 'earned': 5, 'lost': 1},
    {'date': 'May 18', 'earned': 9, 'lost': 0},
  ];

  int _visibleCount = 5;
  bool _loadingMore = false;

  void _loadMore() {
    if (_loadingMore || _visibleCount >= _allDays.length) return;
    setState(() => _loadingMore = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() { _visibleCount = _allDays.length; _loadingMore = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _allDays.take(_visibleCount).toList();
    return ListView.builder(
      controller: widget.scroll,
      itemCount: visible.length + (_visibleCount < _allDays.length ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == visible.length) {
          // Load more button
          return Center(
            child: TextButton(
              onPressed: _loadMore,
              child: _loadingMore
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Show more', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          );
        }
        final day = visible[index];
        final earned = day['earned'] as int;
        final lost = day['lost'] as int;
        final net = earned - lost;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.snow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greyLight, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Center(child: Text('⬡', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day['date'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text('+$earned captured', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                      if (lost > 0) ...[
                        const SizedBox(width: 8),
                        Text('-$lost stolen', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: net >= 0 ? AppColors.primary.withValues(alpha: 0.1) : AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${net >= 0 ? '+' : ''}$net', style: TextStyle(fontWeight: FontWeight.w800, color: net >= 0 ? AppColors.primary : AppColors.red)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// STREAK HISTORY LAZY (shows 10 then loads more)
/// ─────────────────────────────────────────────────────────────────────────────

class _StreakHistoryLazy extends StatefulWidget {
  final ScrollController scroll;
  const _StreakHistoryLazy({required this.scroll});

  @override
  State<_StreakHistoryLazy> createState() => _StreakHistoryLazyState();
}

class _StreakHistoryLazyState extends State<_StreakHistoryLazy> {
  static final _allDays = [
    {'date': 'Today', 'hexes': 5, 'distance': '1.2 km', 'time': '18 min'},
    {'date': 'May 27', 'hexes': 8, 'distance': '2.1 km', 'time': '32 min'},
    {'date': 'May 26', 'hexes': 3, 'distance': '0.8 km', 'time': '12 min'},
    {'date': 'May 25', 'hexes': 6, 'distance': '1.5 km', 'time': '24 min'},
    {'date': 'May 24', 'hexes': 2, 'distance': '0.5 km', 'time': '8 min'},
    {'date': 'May 23', 'hexes': 4, 'distance': '1.0 km', 'time': '15 min'},
    {'date': 'May 22', 'hexes': 7, 'distance': '1.8 km', 'time': '28 min'},
    {'date': 'May 21', 'hexes': 5, 'distance': '1.3 km', 'time': '20 min'},
    {'date': 'May 20', 'hexes': 3, 'distance': '0.7 km', 'time': '11 min'},
    {'date': 'May 19', 'hexes': 9, 'distance': '2.5 km', 'time': '38 min'},
    {'date': 'May 18', 'hexes': 4, 'distance': '1.1 km', 'time': '17 min'},
    {'date': 'May 17', 'hexes': 6, 'distance': '1.6 km', 'time': '25 min'},
    {'date': 'May 16', 'hexes': 2, 'distance': '0.6 km', 'time': '9 min'},
    {'date': 'May 15', 'hexes': 8, 'distance': '2.0 km', 'time': '30 min'},
    {'date': 'May 14', 'hexes': 5, 'distance': '1.4 km', 'time': '22 min'},
  ];

  int _visibleCount = 10;
  bool _loadingMore = false;

  void _loadMore() {
    if (_loadingMore || _visibleCount >= _allDays.length) return;
    setState(() => _loadingMore = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _visibleCount = (_visibleCount + 10).clamp(0, _allDays.length);
          _loadingMore = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _allDays.take(_visibleCount).toList();
    return ListView.builder(
      controller: widget.scroll,
      itemCount: visible.length + (_visibleCount < _allDays.length ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == visible.length) {
          return Center(
            child: TextButton(
              onPressed: _loadMore,
              child: _loadingMore
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Show more', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          );
        }
        final day = visible[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.snow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greyLight, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: Text('🔥', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day['date'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${day['hexes']} hexes · ${day['distance']} · ${day['time']}',
                      style: TextStyle(fontSize: 12, color: AppColors.grey), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('✓', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
      },
    );
  }
}
