/// Trail claim response — returned when hexes are claimed in real-time during a walk.
library;

class TrailClaimResponse {
  final List<TrailHex> claimedCells;
  final int newCellCount;
  final int stolenCount;

  const TrailClaimResponse({
    this.claimedCells = const [],
    this.newCellCount = 0,
    this.stolenCount = 0,
  });

  factory TrailClaimResponse.fromJson(Map<String, dynamic> json) {
    final cells = (json['claimedCells'] as List<dynamic>?)
        ?.map((e) => TrailHex.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    return TrailClaimResponse(
      claimedCells: cells,
      newCellCount: json['newCellCount'] as int? ?? 0,
      stolenCount: json['stolenCount'] as int? ?? 0,
    );
  }
}

class TrailHex {
  final int cellId;
  final List<List<double>> boundary;
  final bool wasStolen;
  final String? previousOwnerName;

  const TrailHex({
    required this.cellId,
    required this.boundary,
    this.wasStolen = false,
    this.previousOwnerName,
  });

  factory TrailHex.fromJson(Map<String, dynamic> json) {
    final rawBoundary = json['boundary'] as List<dynamic>;
    final boundary = rawBoundary
        .map((p) => (p as List<dynamic>).map((v) => (v as num).toDouble()).toList())
        .toList();
    return TrailHex(
      cellId: json['cellId'] as int,
      boundary: boundary,
      wasStolen: json['wasStolen'] as bool? ?? false,
      previousOwnerName: json['previousOwnerName'] as String?,
    );
  }
}

/// Response from the single-point step claim endpoint.
/// If [claimed] is false, the user is still in the same hex.
class StepClaimResponse {
  final bool claimed;
  final int cellId;
  final List<List<double>> boundary;
  final bool wasStolen;
  final String? previousOwnerName;

  const StepClaimResponse({
    this.claimed = false,
    this.cellId = 0,
    this.boundary = const [],
    this.wasStolen = false,
    this.previousOwnerName,
  });

  factory StepClaimResponse.fromJson(Map<String, dynamic> json) {
    final claimed = json['claimed'] as bool? ?? false;
    if (!claimed) return const StepClaimResponse();

    final rawBoundary = json['boundary'] as List<dynamic>? ?? [];
    final boundary = rawBoundary
        .map((p) => (p as List<dynamic>).map((v) => (v as num).toDouble()).toList())
        .toList();
    return StepClaimResponse(
      claimed: true,
      cellId: json['cellId'] as int? ?? 0,
      boundary: boundary,
      wasStolen: json['wasStolen'] as bool? ?? false,
      previousOwnerName: json['previousOwnerName'] as String?,
    );
  }
}
