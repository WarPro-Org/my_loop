/// Player title system — assigns catchy tags based on hex count.
///
/// Inspired by Rocket League's rank titles but themed around territory
/// conquest. In future seasons, titles will be awarded based on points
/// collected per season. For now, they're derived from total hex count.
library;

/// A player title with its display label and minimum hex threshold.
class PlayerTitle {
  final String label;
  final String emoji;
  final int minHexes;

  const PlayerTitle({
    required this.label,
    required this.emoji,
    required this.minHexes,
  });
}

/// All available player titles, ordered from highest to lowest threshold.
const playerTitles = [
  PlayerTitle(label: 'Hex Overlord', emoji: '👑', minHexes: 10000),
  PlayerTitle(label: 'Territory Titan', emoji: '⚡', minHexes: 5000),
  PlayerTitle(label: 'Loop Legend', emoji: '🌀', minHexes: 3000),
  PlayerTitle(label: 'Conquest King', emoji: '🏰', minHexes: 2000),
  PlayerTitle(label: 'Grid Dominator', emoji: '💎', minHexes: 1000),
  PlayerTitle(label: 'Trail Blazer', emoji: '🔥', minHexes: 500),
  PlayerTitle(label: 'Hex Hunter', emoji: '🎯', minHexes: 200),
  PlayerTitle(label: 'Path Finder', emoji: '🧭', minHexes: 50),
  PlayerTitle(label: 'Ground Breaker', emoji: '⬡', minHexes: 10),
  PlayerTitle(label: 'Fresh Feet', emoji: '👟', minHexes: 0),
];

/// Returns the player's current title based on their hex count.
PlayerTitle getTitleForHexes(int hexCount) {
  for (final title in playerTitles) {
    if (hexCount >= title.minHexes) return title;
  }
  return playerTitles.last;
}
