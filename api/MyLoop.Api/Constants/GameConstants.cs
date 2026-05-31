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
    public const double CellAreaSquareMeters = 2_150.0;

    /// <summary>Apothem (center-to-edge) at res 11, ~25m.</summary>
    public const double HexApothemMeters = 25.0;

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
    public const int RevengeDaysWindow = 7;

    // --- Validation ---
    public const int MinDisplayNameLength = 2;
    public const int MaxDisplayNameLength = 20;
    public const int MaxAvatarId = 50;
}
