/// Achievement status model — represents one achievement with user's progress.
library;

class Achievement {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int category;
  final int threshold;
  final int xpReward;
  final bool unlocked;
  final DateTime? unlockedAt;
  final double progress;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    required this.threshold,
    required this.xpReward,
    this.unlocked = false,
    this.unlockedAt,
    this.progress = 0.0,
  });

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '🏆',
      category: json['category'] as int? ?? 0,
      threshold: json['threshold'] as int? ?? 1,
      xpReward: json['xpReward'] as int? ?? 0,
      unlocked: json['unlocked'] as bool? ?? false,
      unlockedAt: json['unlockedAt'] != null
          ? DateTime.tryParse(json['unlockedAt'] as String)
          : null,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String get categoryName => switch (category) {
    0 => 'Capture',
    1 => 'Streak',
    2 => 'Distance',
    3 => 'PvP',
    4 => 'Level',
    5 => 'Leaderboard',
    6 => 'Missions',
    _ => 'Other',
  };
}
