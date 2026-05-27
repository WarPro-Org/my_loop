// Territory cell - one hex on the map
class TerritoryCell {
  final int cellId; // H3 index
  final String ownerId;
  final String ownerColor; // hex color
  final List<List<double>> boundary; // [[lat, lng], ...]

  const TerritoryCell({
    required this.cellId,
    required this.ownerId,
    required this.ownerColor,
    required this.boundary,
  });

  factory TerritoryCell.fromJson(Map<String, dynamic> json) {
    return TerritoryCell(
      cellId: json['cellId'] as int,
      ownerId: json['ownerId'] as String,
      ownerColor: json['ownerColor'] as String,
      boundary: (json['boundary'] as List)
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
    );
  }
}
