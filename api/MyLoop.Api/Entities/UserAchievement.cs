namespace MyLoop.Api.Entities;

/// <summary>
/// A player's unlocked achievement. One row per user per achievement.
/// </summary>
public class UserAchievement
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>Unique achievement identifier (e.g., "first_capture", "streak_30").</summary>
    public string AchievementId { get; set; } = "";

    /// <summary>When the achievement was unlocked.</summary>
    public DateTime UnlockedAt { get; set; }

    /// <summary>XP that was awarded when this achievement was unlocked.</summary>
    public int XpAwarded { get; set; }
}
