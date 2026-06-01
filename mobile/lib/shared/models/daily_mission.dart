/// Daily mission model — represents one of 3 daily challenges for the user.
library;

enum MissionType {
  captureHexes,
  walkDistance,
  stealHex,
  exploreNewArea,
  maintainStreak,
  captureInOneWalk;

  static MissionType fromInt(int value) => MissionType.values[value.clamp(0, values.length - 1)];
}

class DailyMission {
  final String id;
  final MissionType type;
  final String description;
  final int targetValue;
  final int currentProgress;
  final int xpReward;
  final bool isCompleted;
  final DateTime? completedAt;

  const DailyMission({
    required this.id,
    required this.type,
    required this.description,
    required this.targetValue,
    required this.currentProgress,
    required this.xpReward,
    this.isCompleted = false,
    this.completedAt,
  });

  double get progressPercent =>
      targetValue > 0 ? (currentProgress / targetValue).clamp(0.0, 1.0) : 0.0;

  factory DailyMission.fromJson(Map<String, dynamic> json) {
    return DailyMission(
      id: json['id'] as String,
      type: MissionType.fromInt(json['type'] as int? ?? 0),
      description: json['description'] as String? ?? '',
      targetValue: json['targetValue'] as int? ?? 1,
      currentProgress: json['currentProgress'] as int? ?? 0,
      xpReward: json['xpReward'] as int? ?? 0,
      isCompleted: json['isCompleted'] as bool? ?? false,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
    );
  }
}

class XpInfo {
  final int totalXp;
  final int level;
  final int progressXp;
  final int neededXp;
  final double progressPercent;

  const XpInfo({
    this.totalXp = 0,
    this.level = 1,
    this.progressXp = 0,
    this.neededXp = 100,
    this.progressPercent = 0.0,
  });

  factory XpInfo.fromJson(Map<String, dynamic> json) {
    return XpInfo(
      totalXp: json['totalXp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      progressXp: json['progressXp'] as int? ?? 0,
      neededXp: json['neededXp'] as int? ?? 100,
      progressPercent: (json['progressPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
