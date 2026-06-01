/// Model for exploration stats of a single neighborhood (H3 res 8).
library;

class ExplorationNeighborhood {
  final int neighborhoodId;
  final double centerLat;
  final double centerLng;
  final int exploredCount;
  final int totalCount;
  final double percent;

  const ExplorationNeighborhood({
    required this.neighborhoodId,
    required this.centerLat,
    required this.centerLng,
    required this.exploredCount,
    required this.totalCount,
    required this.percent,
  });

  factory ExplorationNeighborhood.fromJson(Map<String, dynamic> json) {
    return ExplorationNeighborhood(
      neighborhoodId: json['neighborhoodId'] as int,
      centerLat: (json['centerLat'] as num).toDouble(),
      centerLng: (json['centerLng'] as num).toDouble(),
      exploredCount: json['exploredCount'] as int,
      totalCount: json['totalCount'] as int,
      percent: (json['percent'] as num).toDouble(),
    );
  }
}
