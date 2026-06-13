/// XP state slice — totalXp, level, progress toward next level.
/// Updated via SignalR XpDelta push or full hydration on login.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:myloop/shared/services/territory_realtime_service.dart';

final _log = Logger('XpSlice');

class XpState {
  final int totalXp;
  final int level;
  final int progressXp;
  final int neededXp;
  final double progressPercent;
  final bool isLoaded;

  const XpState({
    this.totalXp = 0,
    this.level = 1,
    this.progressXp = 0,
    this.neededXp = 100,
    this.progressPercent = 0,
    this.isLoaded = false,
  });
}

class XpSlice extends Notifier<XpState> {
  @override
  XpState build() {
    final realtime = ref.read(territoryRealtimeProvider);
    realtime.onXp.listen((delta) {
      _log.fine('Delta received: +${delta.xpGained} XP, level=${delta.level}');
      state = XpState(
        totalXp: delta.totalXp,
        level: delta.level,
        progressXp: delta.progressXp,
        neededXp: delta.neededXp,
        progressPercent: delta.progressPercent,
        isLoaded: true,
      );
    });
    return const XpState();
  }

  /// Full hydration from game-state endpoint.
  void hydrate(Map<String, dynamic> data) {
    final xp = data['xp'] as Map<String, dynamic>?;
    if (xp == null) return;
    state = XpState(
      totalXp: (xp['totalXp'] as num?)?.toInt() ?? 0,
      level: xp['level'] as int? ?? 1,
      progressXp: xp['progressXp'] as int? ?? 0,
      neededXp: xp['neededXp'] as int? ?? 100,
      progressPercent: (xp['progressPercent'] as num?)?.toDouble() ?? 0,
      isLoaded: true,
    );
  }
}

final xpSliceProvider = NotifierProvider<XpSlice, XpState>(XpSlice.new);
