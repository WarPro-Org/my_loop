/// Walk History Screen — shows paginated list of past territory claims.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/constants/app_constants.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/widgets/offline_notice.dart';

class WalkHistoryScreen extends ConsumerStatefulWidget {
  const WalkHistoryScreen({super.key});

  @override
  ConsumerState<WalkHistoryScreen> createState() => _WalkHistoryScreenState();
}

class _WalkHistoryScreenState extends ConsumerState<WalkHistoryScreen> {
  final List<Map<String, dynamic>> _claims = [];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 1;
  // True when the last load failed because the backend was unreachable, so we
  // can show an explicit offline notice instead of the "No walks yet" empty
  // state, which falsely implies the user has never walked (issue #36).
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    final profile = ref.read(userProfileProvider);
    if (profile.userId == null) return;

    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final results = await api.getWalkHistory(userId: profile.userId!, page: _page);
      setState(() {
        _claims.addAll(results);
        _hasMore = results.length == 20;
        _loading = false;
        _offline = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        // Only surface the offline state when we have nothing else to show;
        // a failed page-2 fetch shouldn't replace already-loaded history.
        _offline = _claims.isEmpty && isServerUnreachable(e);
      });
    }
  }

  void _loadMore() {
    if (_loading || !_hasMore) return;
    _page++;
    _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Walk History'),
        centerTitle: true,
      ),
      body: _claims.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _claims.isEmpty && _offline
              ? const OfflineNotice(
                  title: AppConstants.offlineNoticeTitle,
                  message: AppConstants.offlineWalkHistoryMessage,
                )
              : _claims.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 64, color: AppColors.greyLight),
          const SizedBox(height: 16),
          Text('No walks yet', style: TextStyle(color: AppColors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Complete a loop to see your history here.',
              style: TextStyle(color: AppColors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (scroll) {
        if (scroll.metrics.pixels > scroll.metrics.maxScrollExtent - 200) {
          _loadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: _claims.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _claims.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
              ),
            );
          }
          return _WalkCard(claim: _claims[index]);
        },
      ),
    );
  }
}

class _WalkCard extends StatelessWidget {
  final Map<String, dynamic> claim;
  const _WalkCard({required this.claim});

  @override
  Widget build(BuildContext context) {
    final cellCount = (claim['cellCount'] as num?)?.toInt() ?? 0;
    final areaM2 = (claim['areaM2'] as num?)?.toDouble() ?? 0;
    final createdAt = DateTime.tryParse(claim['createdAt'] ?? '') ?? DateTime.now();
    final areaDisplay = areaM2 >= 10000
        ? '${(areaM2 / 10000).toStringAsFixed(2)} ha'
        : '${areaM2.toInt()} m²';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.greyLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.hexagon, color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cellCount hex${cellCount == 1 ? '' : 'es'} captured',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  areaDisplay,
                  style: TextStyle(color: AppColors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            _formatDate(createdAt),
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
