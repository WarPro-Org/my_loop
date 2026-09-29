namespace MyLoop.Api.Interfaces;

/// <summary>
/// Broadcasts territory ownership changes and personal game state deltas
/// to connected clients in real-time via SignalR.
/// </summary>
public interface ITerritoryNotifier
{
    /// <summary>
    /// Tells each owner about their own hexes' ownership changes: the new owner gets
    /// HexOwnershipChanged and the previous owner gets HexesReleased. Nobody hears about another
    /// player's hexes (single-player 0.1, bug B1).
    /// </summary>
    Task NotifyHexOwnershipChanged(IReadOnlyList<HexChangeEvent> changes);

    /// <summary>
    /// Tells each former owner that the decay reaper released their hexes — the client must
    /// remove them or keep rendering ghost territory until its next viewport poll (#104).
    /// </summary>
    Task NotifyHexesReleasedAsync(IReadOnlyList<HexReleasedEvent> released);

    /// <summary>
    /// Pushes updated user stats to the user's personal SignalR group.
    /// Sent after claims or when user is victim of theft.
    /// </summary>
    Task NotifyUserStatsAsync(Guid userId, UserStatsDelta delta);

    /// <summary>
    /// Pushes XP changes to the user's personal SignalR group.
    /// Sent after XP is awarded (capture, mission completion, achievement).
    /// </summary>
    Task NotifyXpAsync(Guid userId, XpDelta delta);

    /// <summary>
    /// Pushes mission progress updates to the user's personal SignalR group.
    /// Sent after mission ticks or completions.
    /// </summary>
    Task NotifyMissionAsync(Guid userId, MissionDelta delta);

    /// <summary>
    /// Pushes achievement unlocks to the user's personal SignalR group.
    /// Sent when one or more achievements are newly unlocked.
    /// </summary>
    Task NotifyAchievementAsync(Guid userId, AchievementDelta delta);
}

// ─────────────────────────────────────────────────────────────────────────────
// Event Payloads (DTOs for SignalR push)
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>
/// A single hex ownership change, sent only to the players it belongs to (bug B1).
/// </summary>
public record HexChangeEvent(
    string H3Index,
    double CenterLat,
    double CenterLng,
    Guid NewOwnerId,
    string NewOwnerColor,
    string NewOwnerDisplayName,
    Guid? PreviousOwnerId,
    long ParentCellId
);

/// <summary>
/// A hex released by decay, sent as HexesReleased to its former owner only (bug B1).
/// Ids travel as strings: H3 ids exceed 2^53.
/// </summary>
public record HexReleasedEvent(
    string H3Index,
    long ParentCellId,
    Guid OwnerId
);

/// <summary>
/// Personal stat delta pushed to claiming user or theft victim.
/// Uses ABSOLUTE values (not +/-) to avoid ordering issues.
/// </summary>
public record UserStatsDelta(
    int HexCount,
    int TotalHexesCaptured,
    int TotalHexesStolen,
    int Streak,
    bool IsStreakActive,
    double DistanceKm
);

/// <summary>
/// XP change pushed to user after any XP award.
/// </summary>
public record XpDelta(
    int XpGained,
    long TotalXp,
    int Level,
    bool LeveledUp,
    int ProgressXp,
    int NeededXp,
    double ProgressPercent
);

/// <summary>
/// Mission progress update pushed to user after claim.
/// </summary>
public record MissionDelta(
    List<MissionUpdate> Updates,
    bool AllMissionsComplete,
    int BonusXp
);

public record MissionUpdate(
    Guid MissionId,
    string Type,
    int CurrentProgress,
    int TargetValue,
    bool Completed,
    int XpAwarded
);

/// <summary>
/// Achievement unlock notification pushed to user.
/// </summary>
public record AchievementDelta(
    List<AchievementUnlockEvent> Unlocks
);

public record AchievementUnlockEvent(
    string Id,
    string Name,
    string Icon,
    int XpAwarded
);
