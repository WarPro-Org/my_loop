/// Territory cell model for the MyLoop hex-grid map.
///
/// Represents a single H3 hexagonal cell on the map that has been claimed
/// by a player. Used to render colored territory overlays on the map view.
library;

/// A single hexagonal territory cell owned by a player.
///
/// Each cell corresponds to an H3 index at a fixed resolution. The [boundary]
/// polygon is used to draw the hex on the Flutter map, colored with the
/// owner's chosen [ownerColor].
class TerritoryCell {
  final int cellId; // H3 index
  final String ownerId;
  final String ownerColor; // hex color
  final String ownerName;
  final List<List<double>> boundary; // [[lat, lng], ...]
  final DateTime? cooldownExpiresAtUtc;
  final int parentCellId; // H3 res-3 parent (SignalR region group key)

  const TerritoryCell({
    required this.cellId,
    required this.ownerId,
    required this.ownerColor,
    required this.boundary,
    this.ownerName = '',
    this.cooldownExpiresAtUtc,
    this.parentCellId = 0,
  });

  /// Whether this cell is currently under cooldown protection.
  bool get isOnCooldown =>
      cooldownExpiresAtUtc != null &&
      cooldownExpiresAtUtc!.isAfter(DateTime.now().toUtc());

  /// Remaining cooldown duration (zero if expired).
  Duration get cooldownRemaining {
    if (cooldownExpiresAtUtc == null) return Duration.zero;
    final remaining = cooldownExpiresAtUtc!.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Deserializes a territory cell from a JSON map returned by the API.
  ///
  /// The [boundary] field is a nested list of `[lat, lng]` coordinate pairs
  /// forming the hexagon polygon.
  factory TerritoryCell.fromJson(Map<String, dynamic> json) {
    return TerritoryCell(
      cellId: json['cellId'] as int,
      ownerId: json['ownerId'] as String,
      ownerColor: json['ownerColor'] as String,
      ownerName: json['ownerName'] as String? ?? '',
      boundary: (json['boundary'] as List)
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
      cooldownExpiresAtUtc: json['cooldownExpiresAtUtc'] != null
          ? DateTime.parse(json['cooldownExpiresAtUtc'] as String)
          : null,
      parentCellId: json['parentCellId'] as int? ?? 0,
    );
  }
}
