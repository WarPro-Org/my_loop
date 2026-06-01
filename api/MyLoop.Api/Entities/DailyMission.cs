namespace MyLoop.Api.Entities;

/// <summary>
/// A daily mission assigned to a user. 3 missions generated per user per day.
/// Completing all 3 awards a bonus multiplier.
/// </summary>
public class DailyMission
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DateOnly Date { get; set; }

    /// <summary>Mission type (e.g., CaptureHexes, WalkDistance, StealHex, ExploreNewArea).</summary>
    public MissionType Type { get; set; }

    /// <summary>Target value to complete the mission (e.g., 5 hexes, 1000 meters).</summary>
    public int TargetValue { get; set; }

    /// <summary>Current progress toward the target.</summary>
    public int CurrentProgress { get; set; }

    /// <summary>XP reward when completed.</summary>
    public int XpReward { get; set; }

    /// <summary>When the mission was completed (null if still in progress).</summary>
    public DateTime? CompletedAt { get; set; }

    /// <summary>Human-readable description of the mission.</summary>
    public string Description { get; set; } = "";

    public bool IsCompleted => CompletedAt.HasValue;
}

/// <summary>
/// Types of daily missions the system can generate.
/// </summary>
public enum MissionType
{
    CaptureHexes = 0,
    WalkDistance = 1,
    StealHex = 2,
    ExploreNewArea = 3,
    MaintainStreak = 4,
    CaptureInOneWalk = 5,
}
