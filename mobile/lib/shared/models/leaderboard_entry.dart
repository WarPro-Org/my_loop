/// Leaderboard entry model for the MyLoop ranking system.
///
/// Represents one row in the leaderboard, containing a player's rank,
/// territory stats, and display info (avatar, color, name).
/// Returned by the `/api/leaderboard` endpoint.
library;

/// A single entry in the local or global leaderboard.
///
/// Contains everything needed to render one player's row in the
/// leaderboard UI: identity, rank position, and territory metrics.
class LeaderboardEntry {
  final String userId;
  final String displayName;
  final int avatarId;
  final String color;
  final int cellCount;
  final double areaM2;
  final int rank;
  final int hexCount;
  final int streak;
  final double distanceKm;

  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.avatarId,
    required this.color,
    required this.cellCount,
    required this.areaM2,
    required this.rank,
    this.hexCount = 0,
    this.streak = 0,
    this.distanceKm = 0,
  });

  /// Deserializes a leaderboard entry from a JSON map returned by the API.
  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      userId: json['userId'] as String,
      displayName: json['userName'] as String,
      avatarId: (json['userAvatar'] as num).toInt(),
      color: json['userColor'] as String,
      cellCount: (json['cellCount'] as num).toInt(),
      areaM2: (json['areaM2'] as num).toDouble(),
      rank: (json['rank'] as num).toInt(),
      hexCount: (json['userHexCount'] as num?)?.toInt() ?? 0,
      streak: (json['userStreak'] as num?)?.toInt() ?? 0,
      distanceKm: (json['userDistanceKm'] as num?)?.toDouble() ?? 0,
    );
  }
}
