// Leaderboard entry from the API
class LeaderboardEntry {
  final String userId;
  final String displayName;
  final int avatarId;
  final String color;
  final int cellCount;
  final double areaM2;
  final int rank;

  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.avatarId,
    required this.color,
    required this.cellCount,
    required this.areaM2,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      avatarId: json['avatarId'] as int,
      color: json['color'] as String,
      cellCount: json['cellCount'] as int,
      areaM2: (json['areaM2'] as num).toDouble(),
      rank: json['rank'] as int,
    );
  }
}
