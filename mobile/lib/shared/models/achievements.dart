// 100 achievements with 1/2/3 star tiers (like Clash of Clans)
// Each achievement has a name, description, 3 thresholds, and emoji
class Achievement {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final int tier1; // 1 star threshold
  final int tier2; // 2 star threshold
  final int tier3; // 3 star threshold
  final String unit; // "hexes", "km", "walks", etc.

  const Achievement({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.tier1,
    required this.tier2,
    required this.tier3,
    required this.unit,
  });

  // Get stars earned based on current progress
  int getStars(int progress) {
    if (progress >= tier3) return 3;
    if (progress >= tier2) return 2;
    if (progress >= tier1) return 1;
    return 0;
  }
}

// All 100 achievements
const achievements = [
  // TERRITORY (1-20)
  Achievement(id: 'hex_1', name: 'Land Grabber', emoji: '⬡', description: 'Capture hexagons', tier1: 1, tier2: 50, tier3: 500, unit: 'hexes'),
  Achievement(id: 'hex_2', name: 'Territory King', emoji: '👑', description: 'Own hexagons at once', tier1: 10, tier2: 100, tier3: 1000, unit: 'hexes'),
  Achievement(id: 'hex_3', name: 'Hex Collector', emoji: '🧲', description: 'Total hexes ever captured', tier1: 50, tier2: 500, tier3: 5000, unit: 'hexes'),
  Achievement(id: 'hex_4', name: 'Loop Master', emoji: '🔄', description: 'Close loops to capture area', tier1: 5, tier2: 50, tier3: 200, unit: 'loops'),
  Achievement(id: 'hex_5', name: 'Big Loop', emoji: '🌀', description: 'Capture hexes in one loop', tier1: 10, tier2: 30, tier3: 100, unit: 'hexes'),
  Achievement(id: 'hex_6', name: 'Thief', emoji: '🦝', description: 'Steal hexes from others', tier1: 5, tier2: 50, tier3: 500, unit: 'hexes'),
  Achievement(id: 'hex_7', name: 'Defender', emoji: '🛡️', description: 'Reclaim your stolen hexes', tier1: 3, tier2: 30, tier3: 300, unit: 'hexes'),
  Achievement(id: 'hex_8', name: 'Empire Builder', emoji: '🏰', description: 'Own connected hex clusters', tier1: 5, tier2: 20, tier3: 50, unit: 'clusters'),
  Achievement(id: 'hex_9', name: 'Frontier Explorer', emoji: '🧭', description: 'Capture hexes in new areas', tier1: 3, tier2: 10, tier3: 30, unit: 'areas'),
  Achievement(id: 'hex_10', name: 'Hex Hoarder', emoji: '💎', description: 'Hold hexes for 7+ days', tier1: 5, tier2: 50, tier3: 200, unit: 'hexes'),
  Achievement(id: 'hex_11', name: 'Neighborhood Boss', emoji: '🏘️', description: 'Own all hexes in a block', tier1: 1, tier2: 5, tier3: 20, unit: 'blocks'),
  Achievement(id: 'hex_12', name: 'Park Ranger', emoji: '🌳', description: 'Capture hexes in parks', tier1: 5, tier2: 25, tier3: 100, unit: 'hexes'),
  Achievement(id: 'hex_13', name: 'Street Sweeper', emoji: '🧹', description: 'Capture hex rows along roads', tier1: 10, tier2: 50, tier3: 200, unit: 'hexes'),
  Achievement(id: 'hex_14', name: 'Waterfront', emoji: '🌊', description: 'Capture hexes near water', tier1: 5, tier2: 30, tier3: 100, unit: 'hexes'),
  Achievement(id: 'hex_15', name: 'Sky High', emoji: '🏔️', description: 'Capture hexes at elevation', tier1: 3, tier2: 15, tier3: 50, unit: 'hexes'),
  Achievement(id: 'hex_16', name: 'Night Owl', emoji: '🦉', description: 'Capture hexes after 10 PM', tier1: 5, tier2: 30, tier3: 100, unit: 'hexes'),
  Achievement(id: 'hex_17', name: 'Early Bird', emoji: '🐦', description: 'Capture hexes before 7 AM', tier1: 5, tier2: 30, tier3: 100, unit: 'hexes'),
  Achievement(id: 'hex_18', name: 'Weekend Warrior', emoji: '⚔️', description: 'Capture hexes on weekends', tier1: 10, tier2: 100, tier3: 500, unit: 'hexes'),
  Achievement(id: 'hex_19', name: 'Hex Blitz', emoji: '⚡', description: 'Capture 10+ hexes in 5 min', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'hex_20', name: 'Carpet Bomber', emoji: '💣', description: 'Fill a large area at once', tier1: 20, tier2: 50, tier3: 150, unit: 'hexes'),

  // WALKING (21-40)
  Achievement(id: 'walk_1', name: 'First Steps', emoji: '👶', description: 'Complete walks', tier1: 1, tier2: 10, tier3: 100, unit: 'walks'),
  Achievement(id: 'walk_2', name: 'Marathon', emoji: '🏃', description: 'Walk total distance', tier1: 5, tier2: 50, tier3: 500, unit: 'km'),
  Achievement(id: 'walk_3', name: 'Daily Walker', emoji: '📅', description: 'Walk on consecutive days', tier1: 3, tier2: 14, tier3: 60, unit: 'days'),
  Achievement(id: 'walk_4', name: 'Speed Demon', emoji: '💨', description: 'Walk faster than 6 km/h', tier1: 1, tier2: 20, tier3: 100, unit: 'walks'),
  Achievement(id: 'walk_5', name: 'Long Haul', emoji: '🛤️', description: 'Single walk over 5 km', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'walk_6', name: 'Short & Sweet', emoji: '🍬', description: 'Quick walks under 5 min', tier1: 5, tier2: 50, tier3: 200, unit: 'walks'),
  Achievement(id: 'walk_7', name: 'Hour Power', emoji: '⏰', description: 'Walk for 60+ minutes', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'walk_8', name: 'Total Time', emoji: '⌛', description: 'Total walking hours', tier1: 5, tier2: 50, tier3: 500, unit: 'hours'),
  Achievement(id: 'walk_9', name: 'Consistent', emoji: '📊', description: 'Walk same route twice', tier1: 1, tier2: 10, tier3: 50, unit: 'routes'),
  Achievement(id: 'walk_10', name: 'Wanderer', emoji: '🗺️', description: 'Walk in different areas', tier1: 3, tier2: 15, tier3: 50, unit: 'areas'),
  Achievement(id: 'walk_11', name: 'Rain Walker', emoji: '🌧️', description: 'Walk during rain', tier1: 1, tier2: 10, tier3: 50, unit: 'walks'),
  Achievement(id: 'walk_12', name: 'Sunny Side', emoji: '☀️', description: 'Walk on sunny days', tier1: 5, tier2: 30, tier3: 100, unit: 'walks'),
  Achievement(id: 'walk_13', name: 'Cold Snap', emoji: '❄️', description: 'Walk below 5°C', tier1: 1, tier2: 10, tier3: 50, unit: 'walks'),
  Achievement(id: 'walk_14', name: 'Heat Wave', emoji: '🔥', description: 'Walk above 35°C', tier1: 1, tier2: 10, tier3: 50, unit: 'walks'),
  Achievement(id: 'walk_15', name: 'Dog Walker', emoji: '🐕', description: 'Walk in morning hours', tier1: 10, tier2: 50, tier3: 200, unit: 'walks'),
  Achievement(id: 'walk_16', name: 'Commuter', emoji: '🚶', description: 'Walk on weekdays', tier1: 10, tier2: 100, tier3: 500, unit: 'walks'),
  Achievement(id: 'walk_17', name: 'Perfect Loop', emoji: '⭕', description: 'Close loop within 10m', tier1: 1, tier2: 20, tier3: 100, unit: 'times'),
  Achievement(id: 'walk_18', name: 'GPS Artist', emoji: '🎨', description: 'Walk complex shapes', tier1: 1, tier2: 10, tier3: 50, unit: 'shapes'),
  Achievement(id: 'walk_19', name: 'Zigzag', emoji: '⚡', description: 'Walk with many turns', tier1: 5, tier2: 30, tier3: 100, unit: 'walks'),
  Achievement(id: 'walk_20', name: 'Straight Line', emoji: '📏', description: 'Walk in a straight line 1km', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),

  // SOCIAL/COMPETITIVE (41-60)
  Achievement(id: 'social_1', name: 'Rival', emoji: '🤺', description: 'Steal from same player', tier1: 3, tier2: 20, tier3: 100, unit: 'hexes'),
  Achievement(id: 'social_2', name: 'Nemesis', emoji: '😈', description: 'Steal from 10+ players', tier1: 3, tier2: 10, tier3: 30, unit: 'players'),
  Achievement(id: 'social_3', name: 'Top 10', emoji: '🔟', description: 'Reach top 10 local', tier1: 1, tier2: 5, tier3: 20, unit: 'times'),
  Achievement(id: 'social_4', name: 'Number One', emoji: '🥇', description: 'Reach #1 local rank', tier1: 1, tier2: 5, tier3: 20, unit: 'times'),
  Achievement(id: 'social_5', name: 'City Champ', emoji: '🏙️', description: 'Reach top 10 city', tier1: 1, tier2: 3, tier3: 10, unit: 'times'),
  Achievement(id: 'social_6', name: 'National Hero', emoji: '🇮🇳', description: 'Reach top 100 country', tier1: 1, tier2: 3, tier3: 10, unit: 'times'),
  Achievement(id: 'social_7', name: 'Revenge', emoji: '🔥', description: 'Reclaim stolen hex in 24h', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'social_8', name: 'Untouchable', emoji: '🧊', description: 'Hold rank for days', tier1: 3, tier2: 14, tier3: 30, unit: 'days'),
  Achievement(id: 'social_9', name: 'Climber', emoji: '📈', description: 'Improve rank positions', tier1: 5, tier2: 20, tier3: 50, unit: 'positions'),
  Achievement(id: 'social_10', name: 'Newcomer Crusher', emoji: '💪', description: 'Outrank new players', tier1: 5, tier2: 20, tier3: 100, unit: 'players'),
  Achievement(id: 'social_11', name: 'Veteran', emoji: '🎖️', description: 'Play for weeks', tier1: 4, tier2: 12, tier3: 52, unit: 'weeks'),
  Achievement(id: 'social_12', name: 'Loyal Player', emoji: '💛', description: 'Play for months', tier1: 1, tier2: 6, tier3: 12, unit: 'months'),
  Achievement(id: 'social_13', name: 'Territory War', emoji: '⚔️', description: 'Contest same hex 5 times', tier1: 1, tier2: 5, tier3: 20, unit: 'hexes'),
  Achievement(id: 'social_14', name: 'Peaceful', emoji: '☮️', description: 'Days without losing hex', tier1: 3, tier2: 14, tier3: 30, unit: 'days'),
  Achievement(id: 'social_15', name: 'Conqueror', emoji: '🗡️', description: 'Take from 5 players in 1 day', tier1: 1, tier2: 5, tier3: 20, unit: 'times'),
  Achievement(id: 'social_16', name: 'Monopoly', emoji: '🎩', description: 'Own 50%+ of a zone', tier1: 1, tier2: 3, tier3: 10, unit: 'zones'),
  Achievement(id: 'social_17', name: 'David vs Goliath', emoji: '🪨', description: 'Steal from top 3 player', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'social_18', name: 'Underdog', emoji: '🐶', description: 'Climb 10+ ranks in a day', tier1: 1, tier2: 5, tier3: 20, unit: 'times'),
  Achievement(id: 'social_19', name: 'Streak Breaker', emoji: '💥', description: 'Stop a rival\'s streak', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'social_20', name: 'Empire', emoji: '🏯', description: 'Own 200+ hexes at once', tier1: 1, tier2: 3, tier3: 10, unit: 'times'),

  // EXPLORATION (61-80)
  Achievement(id: 'explore_1', name: 'Tourist', emoji: '📸', description: 'Walk in new neighborhoods', tier1: 3, tier2: 10, tier3: 30, unit: 'places'),
  Achievement(id: 'explore_2', name: 'City Explorer', emoji: '🏙️', description: 'Walk in different cities', tier1: 2, tier2: 5, tier3: 15, unit: 'cities'),
  Achievement(id: 'explore_3', name: 'Park Lover', emoji: '🌲', description: 'Walk in parks', tier1: 3, tier2: 15, tier3: 50, unit: 'parks'),
  Achievement(id: 'explore_4', name: 'Bridge Crosser', emoji: '🌉', description: 'Cross bridges during walks', tier1: 1, tier2: 10, tier3: 50, unit: 'bridges'),
  Achievement(id: 'explore_5', name: 'Hill Climber', emoji: '⛰️', description: 'Walk uphill routes', tier1: 5, tier2: 30, tier3: 100, unit: 'times'),
  Achievement(id: 'explore_6', name: 'Beachcomber', emoji: '🏖️', description: 'Walk along beaches', tier1: 1, tier2: 10, tier3: 50, unit: 'walks'),
  Achievement(id: 'explore_7', name: 'Market Walker', emoji: '🛒', description: 'Walk through markets', tier1: 3, tier2: 15, tier3: 50, unit: 'markets'),
  Achievement(id: 'explore_8', name: 'Campus Explorer', emoji: '🎓', description: 'Walk through campuses', tier1: 1, tier2: 5, tier3: 20, unit: 'campuses'),
  Achievement(id: 'explore_9', name: 'Trail Blazer', emoji: '🥾', description: 'Walk on trails', tier1: 3, tier2: 15, tier3: 50, unit: 'trails'),
  Achievement(id: 'explore_10', name: 'Around the Block', emoji: '🔁', description: 'Walk around a full block', tier1: 5, tier2: 30, tier3: 100, unit: 'blocks'),
  Achievement(id: 'explore_11', name: 'Shortcut Finder', emoji: '🗝️', description: 'Walk through alleys', tier1: 5, tier2: 30, tier3: 100, unit: 'alleys'),
  Achievement(id: 'explore_12', name: 'Monument Visitor', emoji: '🗽', description: 'Walk near landmarks', tier1: 3, tier2: 15, tier3: 50, unit: 'landmarks'),
  Achievement(id: 'explore_13', name: 'Night Explorer', emoji: '🌙', description: 'Walk new routes at night', tier1: 3, tier2: 15, tier3: 50, unit: 'routes'),
  Achievement(id: 'explore_14', name: 'Rush Hour', emoji: '🚗', description: 'Walk during peak hours', tier1: 5, tier2: 30, tier3: 100, unit: 'walks'),
  Achievement(id: 'explore_15', name: 'Off the Grid', emoji: '📡', description: 'Walk in low-signal areas', tier1: 1, tier2: 10, tier3: 50, unit: 'walks'),
  Achievement(id: 'explore_16', name: 'Suburbia', emoji: '🏡', description: 'Walk in residential areas', tier1: 10, tier2: 50, tier3: 200, unit: 'walks'),
  Achievement(id: 'explore_17', name: 'Downtown', emoji: '🏢', description: 'Walk in business districts', tier1: 5, tier2: 30, tier3: 100, unit: 'walks'),
  Achievement(id: 'explore_18', name: 'Hidden Gem', emoji: '💎', description: 'Find unclaimed areas', tier1: 5, tier2: 25, tier3: 100, unit: 'areas'),
  Achievement(id: 'explore_19', name: 'Full Coverage', emoji: '📶', description: 'Fill entire zones', tier1: 1, tier2: 5, tier3: 20, unit: 'zones'),
  Achievement(id: 'explore_20', name: 'Border Patrol', emoji: '🚧', description: 'Walk zone boundaries', tier1: 5, tier2: 30, tier3: 100, unit: 'boundaries'),

  // MILESTONES & SPECIAL (81-100)
  Achievement(id: 'mile_1', name: 'One Week', emoji: '📅', description: 'Play for 7 days', tier1: 7, tier2: 7, tier3: 7, unit: 'days'),
  Achievement(id: 'mile_2', name: 'One Month', emoji: '🗓️', description: 'Play for 30 days', tier1: 30, tier2: 30, tier3: 30, unit: 'days'),
  Achievement(id: 'mile_3', name: '100 Walks', emoji: '💯', description: 'Complete 100 walks', tier1: 100, tier2: 100, tier3: 100, unit: 'walks'),
  Achievement(id: 'mile_4', name: '10K Steps', emoji: '👟', description: 'Walk 10,000 steps in a day', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'mile_5', name: 'Centurion', emoji: '🏛️', description: 'Own 100 hexes', tier1: 100, tier2: 100, tier3: 100, unit: 'hexes'),
  Achievement(id: 'mile_6', name: 'Half Marathon', emoji: '🎽', description: 'Walk 21km total', tier1: 21, tier2: 21, tier3: 21, unit: 'km'),
  Achievement(id: 'mile_7', name: 'Full Marathon', emoji: '🏅', description: 'Walk 42km total', tier1: 42, tier2: 42, tier3: 42, unit: 'km'),
  Achievement(id: 'mile_8', name: 'Ultra', emoji: '🦸', description: 'Walk 100km total', tier1: 100, tier2: 100, tier3: 100, unit: 'km'),
  Achievement(id: 'mile_9', name: 'Thousand', emoji: '🎯', description: 'Capture 1000 total hexes', tier1: 1000, tier2: 1000, tier3: 1000, unit: 'hexes'),
  Achievement(id: 'mile_10', name: 'Iron Will', emoji: '🦾', description: '30-day streak', tier1: 30, tier2: 30, tier3: 30, unit: 'days'),
  Achievement(id: 'mile_11', name: 'Unstoppable', emoji: '🚂', description: '60-day streak', tier1: 60, tier2: 60, tier3: 60, unit: 'days'),
  Achievement(id: 'mile_12', name: 'Legend', emoji: '🌟', description: '100-day streak', tier1: 100, tier2: 100, tier3: 100, unit: 'days'),
  Achievement(id: 'mile_13', name: 'Early Adopter', emoji: '🌱', description: 'Join in first month', tier1: 1, tier2: 1, tier3: 1, unit: 'joined'),
  Achievement(id: 'mile_14', name: 'Perfectionist', emoji: '✨', description: 'Get 3 stars on 50 achievements', tier1: 10, tier2: 25, tier3: 50, unit: 'achievements'),
  Achievement(id: 'mile_15', name: 'Collector', emoji: '🏆', description: 'Unlock any 50 achievements', tier1: 10, tier2: 25, tier3: 50, unit: 'achievements'),
  Achievement(id: 'mile_16', name: 'Daily Grind', emoji: '☕', description: 'Complete daily challenges', tier1: 7, tier2: 30, tier3: 100, unit: 'challenges'),
  Achievement(id: 'mile_17', name: 'Overachiever', emoji: '🚀', description: 'Exceed daily goal by 3x', tier1: 1, tier2: 10, tier3: 50, unit: 'times'),
  Achievement(id: 'mile_18', name: 'Comeback', emoji: '🔄', description: 'Return after 7 day break', tier1: 1, tier2: 3, tier3: 10, unit: 'times'),
  Achievement(id: 'mile_19', name: 'No Days Off', emoji: '💪', description: 'Walk every day for a month', tier1: 1, tier2: 3, tier3: 12, unit: 'months'),
  Achievement(id: 'mile_20', name: 'Champion', emoji: '🏆', description: 'Get all 3-star achievements', tier1: 25, tier2: 50, tier3: 100, unit: 'achievements'),
];
