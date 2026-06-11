/// Model for exploration stats of a single area where user owns hexes.
library;

class ExplorationNeighborhood {
  final int neighborhoodId;
  final double centerLat;
  final double centerLng;
  final int exploredCount;
  final int ownedCount;
  final int totalCount;
  final double percent;
  final String areaName;

  const ExplorationNeighborhood({
    required this.neighborhoodId,
    required this.centerLat,
    required this.centerLng,
    required this.exploredCount,
    required this.ownedCount,
    required this.totalCount,
    required this.percent,
    required this.areaName,
  });

  factory ExplorationNeighborhood.fromJson(Map<String, dynamic> json) {
    return ExplorationNeighborhood(
      neighborhoodId: json['neighborhoodId'] as int,
      centerLat: (json['centerLat'] as num).toDouble(),
      centerLng: (json['centerLng'] as num).toDouble(),
      exploredCount: json['exploredCount'] as int,
      ownedCount: json['ownedCount'] as int? ?? 0,
      totalCount: json['totalCount'] as int,
      percent: (json['percent'] as num).toDouble(),
      areaName: json['areaName'] as String? ?? '',
    );
  }
}
