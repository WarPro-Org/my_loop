namespace MyLoop.Api.Constants;

/// <summary>
/// All achievement definitions. Each achievement has:
/// - A unique string ID (stable, never changes)
/// - Category for UI grouping
/// - A threshold the player must reach
/// - XP reward on unlock
/// - Display info (name, description, icon)
/// </summary>
public static class Achievements
{
    public static readonly AchievementDefinition[] All = GetAll();

    private static AchievementDefinition[] GetAll() =>
    [
        // ─── CAPTURE ─────────────────────────────────────────────────
        new("first_capture", AchievementCategory.Capture, "First Steps", "Capture your first hex", "⬡", 1, 25),
        new("capture_10", AchievementCategory.Capture, "Pathfinder", "Capture 10 hexes", "🛤️", 10, 50),
        new("capture_50", AchievementCategory.Capture, "Trailblazer", "Capture 50 hexes", "🔥", 50, 100),
        new("capture_100", AchievementCategory.Capture, "Centurion", "Capture 100 hexes", "💯", 100, 150),
        new("capture_500", AchievementCategory.Capture, "Conqueror", "Capture 500 hexes", "⚔️", 500, 300),
        new("capture_1000", AchievementCategory.Capture, "Warlord", "Capture 1,000 hexes", "👑", 1000, 500),
        new("capture_5000", AchievementCategory.Capture, "Emperor", "Capture 5,000 hexes", "🏰", 5000, 1000),

        // ─── STREAK ──────────────────────────────────────────────────
        new("streak_3", AchievementCategory.Streak, "Getting Started", "Maintain a 3-day streak", "🌱", 3, 30),
        new("streak_7", AchievementCategory.Streak, "Consistent", "Maintain a 7-day streak", "📅", 7, 75),
        new("streak_14", AchievementCategory.Streak, "Committed", "Maintain a 14-day streak", "💪", 14, 150),
        new("streak_30", AchievementCategory.Streak, "Dedicated", "Maintain a 30-day streak", "🏆", 30, 300),
        new("streak_60", AchievementCategory.Streak, "Unstoppable", "Maintain a 60-day streak", "⚡", 60, 500),
        new("streak_100", AchievementCategory.Streak, "Legendary", "Maintain a 100-day streak", "🌟", 100, 1000),

        // ─── DISTANCE ────────────────────────────────────────────────
        new("distance_1km", AchievementCategory.Distance, "First Kilometer", "Walk 1 km total", "👟", 1, 30),
        new("distance_10km", AchievementCategory.Distance, "Walker", "Walk 10 km total", "🚶", 10, 75),
        new("distance_50km", AchievementCategory.Distance, "Hiker", "Walk 50 km total", "🥾", 50, 200),
        new("distance_100km", AchievementCategory.Distance, "Trekker", "Walk 100 km total", "🏔️", 100, 400),
        new("distance_500km", AchievementCategory.Distance, "Pilgrim", "Walk 500 km total", "🌍", 500, 800),

        // ─── STEAL / PVP ────────────────────────────────────────────
        new("steal_1", AchievementCategory.Pvp, "First Blood", "Steal your first hex", "🗡️", 1, 50),
        new("steal_10", AchievementCategory.Pvp, "Raider", "Steal 10 hexes", "💀", 10, 100),
        new("steal_50", AchievementCategory.Pvp, "Pirate", "Steal 50 hexes", "☠️", 50, 250),
        new("steal_200", AchievementCategory.Pvp, "Overlord", "Steal 200 hexes", "🐉", 200, 500),

        // ─── LEVEL ───────────────────────────────────────────────────
        new("level_5", AchievementCategory.Level, "Apprentice", "Reach Level 5", "⭐", 5, 50),
        new("level_10", AchievementCategory.Level, "Warrior", "Reach Level 10", "🌟", 10, 150),
        new("level_25", AchievementCategory.Level, "Master", "Reach Level 25", "💫", 25, 400),
        new("level_50", AchievementCategory.Level, "Legend", "Reach Level 50", "🔮", 50, 1000),

        // ─── LEADERBOARD ─────────────────────────────────────────────
        new("top3_first", AchievementCategory.Leaderboard, "Podium", "Finish top 3 on leaderboard", "🥉", 1, 100),
        new("top3_ten", AchievementCategory.Leaderboard, "Regular Champion", "Finish top 3 ten times", "🥇", 10, 300),

        // ─── MISSIONS ────────────────────────────────────────────────
        new("missions_complete_1", AchievementCategory.Missions, "Mission Accepted", "Complete all daily missions", "✅", 1, 50),
        new("missions_complete_7", AchievementCategory.Missions, "Weekly Warrior", "Complete all missions 7 days", "📋", 7, 200),
        new("missions_complete_30", AchievementCategory.Missions, "Mission Master", "Complete all missions 30 days", "🎖️", 30, 500),
    ];

    public static AchievementDefinition? GetById(string id) =>
        All.FirstOrDefault(a => a.Id == id);
}

public class AchievementDefinition
{
    public string Id { get; }
    public AchievementCategory Category { get; }
    public string Name { get; }
    public string Description { get; }
    public string Icon { get; }
    public int Threshold { get; }
    public int XpReward { get; }

    public AchievementDefinition(string id, AchievementCategory category, string name, string description, string icon, int threshold, int xpReward)
    {
        Id = id;
        Category = category;
        Name = name;
        Description = description;
        Icon = icon;
        Threshold = threshold;
        XpReward = xpReward;
    }
}

public enum AchievementCategory
{
    Capture = 0,
    Streak = 1,
    Distance = 2,
    Pvp = 3,
    Level = 4,
    Leaderboard = 5,
    Missions = 6,
}
