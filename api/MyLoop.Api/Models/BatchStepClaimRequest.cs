namespace MyLoop.Api.Models;

/// <summary>
/// Batch of GPS step points captured during a walk, drained from the client's
/// write-ahead log. Processed atomically: single transaction, single save,
/// consolidated push notifications. Designed for resilient offline-first claiming.
/// </summary>
public class BatchStepClaimRequest
{
    public Guid UserId { get; set; }

    /// <summary>
    /// Client's local date in yyyy-MM-dd format. Used for streak computation
    /// to avoid UTC timezone drift (e.g., walking at 11pm IST should count
    /// as same day, not next-day UTC). Server clamps to within ±1 day of UTC.
    /// </summary>
    public string? LocalDate { get; set; }

    public List<BatchStepPoint> Points { get; set; } = [];
}

public class BatchStepPoint
{
    /// <summary>Client-generated correlation ID (UUID) — echoed back so the
    /// client can match each result to its queued entry and remove from WAL.</summary>
    public string ClientId { get; set; } = "";
    public double Lat { get; set; }
    public double Lng { get; set; }
    /// <summary>Client-side timestamp when point was captured (ISO 8601).</summary>
    public DateTime CapturedAt { get; set; }
}

public class BatchStepClaimResponse
{
    public List<BatchStepResult> Results { get; set; } = [];

    /// <summary>Final user stats AFTER batch applied (absolute values).</summary>
    public BatchStepStats Stats { get; set; } = new();

    /// <summary>Aggregated XP gained across the batch + new totals.</summary>
    public BatchStepXp Xp { get; set; } = new();

    /// <summary>Mission updates (deduplicated to final progress per mission).</summary>
    public List<BatchMissionUpdate> Missions { get; set; } = [];

    /// <summary>Achievements unlocked during this batch.</summary>
    public List<AchievementUnlockedDto> Achievements { get; set; } = [];
}

public class BatchStepResult
{
    public string ClientId { get; set; } = "";
    public bool Claimed { get; set; }
    public long? CellId { get; set; }
    public double[][]? Boundary { get; set; }
    public bool WasStolen { get; set; }
    public string? PreviousOwnerName { get; set; }
    /// <summary>Reason if not claimed: "owned" | "cooldown" | "duplicate".</summary>
    public string? SkipReason { get; set; }
}

public class BatchStepStats
{
    public int HexCount { get; set; }
    public int TotalHexesCaptured { get; set; }
    public int TotalHexesStolen { get; set; }
    public int Streak { get; set; }
    public bool IsStreakActive { get; set; }
    public double DistanceKm { get; set; }
}

public class BatchStepXp
{
    public int XpGained { get; set; }
    public long TotalXp { get; set; }
    public int Level { get; set; }
    public bool LeveledUp { get; set; }
    public int ProgressXp { get; set; }
    public int NeededXp { get; set; }
    public double ProgressPercent { get; set; }
}

public class BatchMissionUpdate
{
    public Guid MissionId { get; set; }
    public string Type { get; set; } = "";
    public int CurrentProgress { get; set; }
    public int TargetValue { get; set; }
    public bool Completed { get; set; }
    public int XpAwarded { get; set; }
}
