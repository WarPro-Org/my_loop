namespace MyLoop.Api.DTOs;

/// <summary>Response DTO for leaderboard entries (returned from API).</summary>
public record LeaderboardResponse(
    Guid UserId,
    string DisplayName,
    int AvatarId,
    string Color,
    int HexCount,
    int CellCount,
    int Rank
);

/// <summary>Response DTO for user profile (public view).</summary>
public record UserProfileResponse(
    Guid UserId,
    string DisplayName,
    int AvatarId,
    string Color,
    int HexCount,
    int Streak,
    int MaxStreak,
    double DistanceKm,
    int TopThreeFinishes,
    bool IsStreakActive,
    string? JoinedAt
);

/// <summary>Response DTO for claim submission result.</summary>
public record ClaimResponse(
    Guid Id,
    int CellCount,
    double AreaM2,
    int StolenFromOthers,
    double[][][] Boundaries
);

/// <summary>Response DTO for territory cells in viewport.</summary>
public record TerritoryCellResponse(
    long CellId,
    string? Boundary,
    Guid OwnerId,
    string? OwnerColor,
    string? OwnerName
);
