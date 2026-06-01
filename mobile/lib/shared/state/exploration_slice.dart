/// Exploration state slice — neighborhood coverage percentages.
/// NOT pushed via SignalR (low frequency, on-demand refresh only).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myloop/shared/models/exploration_neighborhood.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';

class ExplorationState {
  final List<ExplorationNeighborhood> neighborhoods;
  final bool isLoaded;

  const ExplorationState({
    this.neighborhoods = const [],
    this.isLoaded = false,
  });
}

class ExplorationSlice extends Notifier<ExplorationState> {
  @override
  ExplorationState build() => const ExplorationState();

  /// Full hydration from game-state endpoint.
  void hydrate(List<dynamic> raw) {
    final neighborhoods = raw
        .map((e) => ExplorationNeighborhood.fromJson(e as Map<String, dynamic>))
        .toList();
    state = ExplorationState(neighborhoods: neighborhoods, isLoaded: true);
  }

  /// Manual refresh (pull-to-refresh or after walk ends).
  Future<void> refresh() async {
    final api = ref.read(apiServiceProvider);
    final profile = ref.read(userProfileProvider);
    if (profile.userId == null) return;
    final data = await api.getExplorationStats(
      userId: profile.userId!,
      lat: 0,
      lng: 0,
    );
    state = ExplorationState(neighborhoods: data, isLoaded: true);
  }
}

final explorationSliceProvider =
    NotifierProvider<ExplorationSlice, ExplorationState>(ExplorationSlice.new);
