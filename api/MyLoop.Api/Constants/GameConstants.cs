namespace MyLoop.Api.Constants;

/// <summary>
/// All game-wide constants in one place — no magic numbers scattered in code.
/// </summary>
public static class GameConstants
{
    // --- Territory Claim Rules ---
    public const int MinGpsPointsPerClaim = 10;
    public const int MinPointsForPolygon = 4;
    public const double MinWalkDistanceMeters = 200.0;
    public const double MaxClaimAreaSquareMeters = 5_000_000.0; // 5 km²
    public const int MaxClaimsPerDay = 20;
    public const double LoopClosureDistanceMeters = 50.0;
    public const int MinLoopPoints = 20;
    public const int LoopSkipNeighbors = 10;
    public const double MinFillAreaSquareMeters = 5_000.0;
    public const double DeduplicationOverlapThreshold = 0.80;
    public const double CellCooldownHours = 5.0;

    // --- H3 Hex Grid ---
    /// <summary>
    /// H3 resolution 11: edge ~29m, circumradius ~29m, area ~2,150 m².
    /// Produces edge-to-edge tessellating hexes that feel "earnable" per walk.
    /// </summary>
    public const int H3Resolution = 11;
    public const int H3ParentResolution = 3;
    public const int H3NeighborhoodResolution = 8;
    public const double CellAreaSquareMeters = 2_150.0;

    // --- Decay ---
    /// <summary>Hex cells decay after this many days without the owner walking through them.</summary>
    public const int DecayDays = 7;

    /// <summary>Total child cells at res-11 within one res-8 neighborhood hex (7^3 = 343).</summary>
    public const int CellsPerNeighborhood = 343;

    // --- Viewport / Query Limits ---
    public const int MaxViewportCells = 500;
    public const int MaxUserTerritoryCells = 2000;
    public const int MaxPreviewPathLength = 10_000;

    // --- GPS / Geolocation ---
    public const double EarthRadiusMeters = 6_371_000.0;
    public const double MetersPerDegreeLat = 111_320.0;

    // --- Leaderboard ---
    public const int LeaderboardTopCount = 20;
    public const int LeaderboardRetentionDays = 7;
    public const int MaxHistoryDepth = 50;
    public const int MaxStolenCellsResponse = 200;
    public const int MaxStolenDaysLookback = 30;

    // --- Validation ---
    public const int MinDisplayNameLength = 2;
    public const int MaxDisplayNameLength = 20;
    public const int MaxAvatarId = 50;

    // --- XP & Levels ---
    public const int XpPerHexCaptured = 10;
    public const int XpPerHexStolen = 25;
    public const int XpPerKmWalked = 50;
    public const int XpStreakBonus = 20; // per day of active streak
    public const int XpMissionComplete = 0; // awarded per-mission (varies)
    public const int XpAllMissionsBonus = 100; // bonus for completing all 3 daily
    public const int MissionsPerDay = 3;

    /// <summary>XP threshold to reach a given level. Level 1 = 0 XP, Level 2 = 100 XP, Level 3 = 400 XP, Level 10 = 8100 XP.</summary>
    /// <summary>XP threshold to reach a given level. Level 1 = 0 XP, Level 2 = 100 XP, Level 10 = 8100 XP.</summary>
    public static int XpForLevel(int level) => (level - 1) * (level - 1) * 100;
    public static int LevelFromXp(long xp)
    {
        var level = 1 + (int)Math.Sqrt(xp / 100.0);
        return Math.Max(1, level);
    }
}
