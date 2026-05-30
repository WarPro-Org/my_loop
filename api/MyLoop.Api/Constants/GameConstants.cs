namespace MyLoop.Api.Constants;

/// <summary>
/// All game-wide constants in one place — no magic numbers scattered in code.
/// </summary>
public static class GameConstants
{
    // --- Territory Claim Rules ---
    public const int MinGpsPointsPerClaim = 10;
    public const double MinWalkDistanceMeters = 200.0;
    public const double MaxClaimAreaSquareMeters = 5_000_000.0; // 5 km²
    public const int MaxClaimsPerDay = 20;
    public const double LoopClosureDistanceMeters = 50.0;
    public const double MinFillAreaSquareMeters = 5_000.0;

    // --- H3 Hex Grid ---
    public const int H3Resolution = 10;
    public const int H3ParentResolution = 3;
    public const double CellAreaSquareMeters = 15_047.0;
    public const double HexVisualRadiusMeters = 25.0;

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
