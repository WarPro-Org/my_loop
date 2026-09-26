using System.Collections.Frozen;

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
    /// <summary>Hard cap on cells assigned in one claim (secondary guard alongside area).</summary>
    public const int MaxCellsPerClaim = 3000;
    /// <summary>
    /// Max distinct walks (Claims) per day, counted by UTC day ON PURPOSE: this is an
    /// anti-abuse bound with a fixed window immune to client-supplied local dates — unlike
    /// streaks and missions, which follow the player's local day via GameDay.Resolve (#106).
    /// </summary>
    public const int MaxClaimsPerDay = 20;
    public const double DeduplicationOverlapThreshold = 0.80;
    /// <summary>
    /// Steal-back protection window: a just-captured cell cannot be stolen for this long.
    /// A full day prevents ping-pong ownership flipping and matches the daily play loop
    /// (missions, streaks, daily leaderboard finishes).
    /// </summary>
    public const double CellCooldownHours = 24.0;

    // --- H3 Hex Grid ---
    /// <summary>
    /// H3 resolution 11: edge ~29m, circumradius ~29m, area ~2,150 m².
    /// Produces edge-to-edge tessellating hexes that feel "earnable" per walk.
    /// </summary>
    public const int H3Resolution = 11;
    public const int H3ParentResolution = 3;
    public const int H3NeighborhoodResolution = 8;
    /// <summary>
    /// Viewport bbox span (per axis, degrees) beyond which region pruning is skipped:
    /// a wider box would need thousands of res-3 parents, and a giant ANY() array pushes
    /// the planner off the index — the coordinate filter alone serves zoomed-out maps (#114).
    /// </summary>
    public const double MaxRegionPruneSpanDegrees = 10.0;
    public const double CellAreaSquareMeters = 2_150.0;

    // --- Decay ---
    /// <summary>Default hex decay for local territory (same city).</summary>
    public const int DecayDays = 7;
    /// <summary>Decay for hexes in a different city but same state/region.</summary>
    public const int DecayDaysOtherCity = 15;
    /// <summary>Decay for hexes in a different state/region but same country.</summary>
    public const int DecayDaysOtherRegion = 30;
    /// <summary>Decay for hexes in a different country but same continent.</summary>
    public const int DecayDaysOtherCountry = 60;
    /// <summary>Decay for hexes on a different continent.</summary>
    public const int DecayDaysOtherContinent = 90;

    /// <summary>
    /// Returns decay days from the great-circle distance between a hex and the user's home,
    /// approximating the city/region/country/continent tiers without reverse-geocoding
    /// (ML-ERR-004 — geocoding is I/O and must never run inside the claim transaction).
    /// </summary>
    public static int GetDecayDaysForDistance(double distanceKm)
    {
        if (distanceKm < 30) return DecayDays;
        if (distanceKm < 200) return DecayDaysOtherCity;
        if (distanceKm < 1000) return DecayDaysOtherRegion;
        if (distanceKm < 5000) return DecayDaysOtherCountry;
        return DecayDaysOtherContinent;
    }

    /// <summary>Total child cells at res-11 within one res-8 neighborhood hex (7^3 = 343).</summary>
    public const int CellsPerNeighborhood = 343;

    // --- Streak ---
    /// <summary>
    /// Days of no claim (measured in UTC) after which the background job breaks a streak.
    /// The claim path records LastClaimDate from the player's LOCAL date, clamped to UTC ±1 by
    /// TerritoryService.ResolveStreakDate. A streak that is still alive in SOME timezone can
    /// therefore have a LastClaimDate as old as (UTC today − 2). The UTC-only cleanup must not
    /// break those, so it only breaks LastClaimDate &lt; (UTC today − this value). At 2, the job
    /// never breaks a streak an honest local-date claim would still consider alive, and breaks it
    /// once it is definitely dead in every timezone.
    /// </summary>
    public const int StreakBreakUtcGraceDays = 2;

    // --- Viewport / Query Limits ---
    public const int MaxViewportCells = 500;
    /// <summary>Valid WGS84 latitude range (degrees) for a client-supplied viewport bbox.</summary>
    public const double MinLatitudeDegrees = -90.0;
    public const double MaxLatitudeDegrees = 90.0;
    /// <summary>Valid WGS84 longitude range (degrees) for a client-supplied viewport bbox.</summary>
    public const double MinLongitudeDegrees = -180.0;
    public const double MaxLongitudeDegrees = 180.0;
    public const int MaxUserTerritoryCells = 2000;
    public const int MaxPreviewPathLength = 10_000;

    /// <summary>
    /// Hard cap on GPS points accepted in a single claim/trail submission (DoS guard).
    /// Sized to a walking-realistic ceiling: 6 h × 1 point / 5 s ≈ 4,320, rounded to 6,000.
    /// No legitimate walk exceeds this; larger submissions are rejected 400 (see
    /// ClaimsController). Bounds the loop-closure spatial scan (#116 / ML-ERR-019).
    /// </summary>
    public const int MaxClaimPathPoints = 6_000;

    /// <summary>
    /// Hard cap on points in one batch-step claim. Single source for the controller's 400
    /// guard and the service's fail-loud check — the pair must never drift apart, because a
    /// batch that is truncated instead of rejected leaves un-ACKed points jamming the
    /// client's write-ahead log forever (#117). The mobile drainer sends at most 50.
    /// </summary>
    public const int MaxBatchStepPoints = 200;

    // --- GPS / Geolocation ---
    public const double EarthRadiusMeters = 6_371_000.0;
    public const double MetersPerDegreeLat = 111_320.0;

    // --- Leaderboard ---
    public const int LeaderboardTopCount = 20;
    public const int LeaderboardRetentionDays = 7;
    public const int MaxHistoryDepth = 50;
    public const int MaxStolenCellsResponse = 200;
    public const int MaxStolenDaysLookback = 30;
    /// <summary>Most-recent days of claim history summarised for the Home "Hex History" section.</summary>
    public const int ClaimHistoryDays = 30;

    // --- Validation ---
    public const int MinDisplayNameLength = 2;
    public const int MaxDisplayNameLength = 20;

    /// <summary>
    /// Name tokens this short or shorter are treated as letters typed one at a time and joined
    /// back together for moderation ("s-h-i-t", "f u c k"). Kept at 1 because two-letter tokens
    /// are real name parts (Li, Wu, Ho, Si Ki, Su Ka) that would join into blocked terms.
    /// Mirrors MAX_SPELLED_OUT_TOKEN_LENGTH in scripts/moderation/build_name_blocklist.py.
    /// </summary>
    public const int MaxSpelledOutTokenLength = 1;

    /// <summary>
    /// Shortest severe term that is still matched when it crosses the space between a single
    /// letter and the next word ("N iggerboy"). At 4, real initial + surname names form terms
    /// (S Luther → "slut", P Ornstead → "porn"). Mirrors MIN_SPANNING_SEVERE_TERM_LENGTH in
    /// scripts/moderation/build_name_blocklist.py, which checks the corpora at this length.
    /// </summary>
    public const int MinSpanningSevereTermLength = 5;

    /// <summary>
    /// Number of avatars in the client catalogue — mirrors <c>avatarEmojis</c> in
    /// mobile/lib/shared/widgets/avatar_widget.dart; valid ids are 0..AvatarCount-1.
    /// Ids are positional and permanent: append only, never reorder or delete, and bump
    /// this in the same change. The client clamps unknown ids, so a wider server range
    /// stores values the app renders as a different avatar (DR-001, #188).
    /// </summary>
    public const int AvatarCount = 12;

    /// <summary>
    /// Allowed player colours — mirrors <c>playerColors</c> in
    /// mobile/lib/shared/widgets/color_picker_row.dart, compared exactly (the client sends
    /// these uppercase literals and matches the stored value case-sensitively). A free-form
    /// hex let players pick invisible or rival-matching territory colours (DR-001, #188).
    /// </summary>
    public static readonly FrozenSet<string> PlayerColors = new[]
    {
        "#00D4AA", "#1CB0F6", "#FF4B4B", "#FF9600",
        "#A560E8", "#FFC800", "#FF6B81", "#2ED8A3",
    }.ToFrozenSet(StringComparer.Ordinal);

    // --- Name moderation (DR-002b, #190) ---
    /// <summary>Distinct reporters, since the case (re)opened, that auto-hide a name.</summary>
    public const int NameReportHideThreshold = 3;
    /// <summary>Reports one player may file per UTC day (anti-spam).</summary>
    public const int MaxNameReportsPerReporterPerDay = 10;
    /// <summary>Moderator-confirmed hides that lock renaming until a moderator unlocks it.</summary>
    public const int NameStrikesToLock = 2;
    /// <summary>Most players one account may block (bounds the list every client downloads).</summary>
    public const int MaxBlocksPerUser = 200;
    /// <summary>
    /// Stands in for a blocked player's name in theft alerts, push and in-app alike (Flutter:
    /// <c>blockedActorLabel</c> in <c>blocked_users.dart</c>). Neutral, so a lock screen never shows
    /// that someone was blocked (DR-002b §7.1).
    /// </summary>
    public const string BlockedActorLabel = "A player";
    /// <summary>Users loaded per page by the moderator rescan.</summary>
    public const int NameRescanPageSize = 500;
    /// <summary>Column size for stored name snapshots — above MaxDisplayNameLength so legacy names fit.</summary>
    public const int MaxModeratedNameLength = 64;
    /// <summary>Firebase UIDs are at most 128 characters.</summary>
    public const int MaxFirebaseUidLength = 128;
    /// <summary>Shown in place of a hidden name, followed by the first hex digits of the user id.</summary>
    public const string HiddenNamePrefix = "Player#";
    public const int HiddenNameIdDigits = 4;

    /// <summary>
    /// Minimum days between home-location changes. Home drives decay distance and the
    /// city/country leaderboard scope, so unrestricted re-homing lets a player game both
    /// (anti-cheat, #84). The first set (onboarding) is always allowed.
    /// </summary>
    public const int HomeChangeCooldownDays = 30;

    // --- XP & Levels ---
    public const int XpPerHexCaptured = 10;
    public const int XpPerHexStolen = 25;
    public const int XpPerKmWalked = 50;
    public const int XpStreakBonus = 20; // per day of active streak
    public const int XpMissionComplete = 0; // awarded per-mission (varies)
    public const int XpAllMissionsBonus = 100; // bonus for completing all 3 daily
    public const int MissionsPerDay = 3;

    /// <summary>XP threshold to reach a given level. Level 1 = 0 XP, Level 2 = 100 XP, Level 3 = 400 XP, Level 10 = 8100 XP.</summary>
    public static int XpForLevel(int level) => (level - 1) * (level - 1) * 100;
    public static int LevelFromXp(long xp)
    {
        var level = 1 + (int)Math.Sqrt(xp / 100.0);
        return Math.Max(1, level);
    }
}
