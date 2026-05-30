namespace MyLoop.Api.Models;

/// <summary>
/// Response returned after a successful territory claim.
/// </summary>
public class ClaimResponse
{
    public Guid Id { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
    public int StolenFromOthers { get; set; }
    public List<double[][]> Boundaries { get; set; } = [];
}

/// <summary>
/// A single territory cell as returned in the viewport query.
/// </summary>
public class TerritoryCellResponse
{
    public long CellId { get; set; }
    public double[][]? Boundary { get; set; }
    public Guid OwnerId { get; set; }
    public string? OwnerColor { get; set; }
    public string? OwnerName { get; set; }
    public DateTime? CooldownExpiresAtUtc { get; set; }
}

/// <summary>
/// Territory stats for a single user.
/// </summary>
public class TerritoryStatsResponse
{
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
}

/// <summary>
/// Response for stolen cells query.
/// </summary>
public class StolenCellsResponse
{
    public int TotalStolen { get; set; }
    public DateTime Since { get; set; }
    public List<StealerSummary> ByStealer { get; set; } = [];
    public List<StolenCellDetail> Cells { get; set; } = [];
}

public class StealerSummary
{
    public Guid UserId { get; set; }
    public int CellsStolen { get; set; }
}

public class StolenCellDetail
{
    public long CellId { get; set; }
    public Guid ToUserId { get; set; }
    public DateTime TransferredAt { get; set; }
    public Guid ClaimId { get; set; }
}

/// <summary>
/// A single entry in a user's claim history (hex history on home page).
/// </summary>
public class ClaimHistoryEntry
{
    public Guid ClaimId { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
    public DateTime Date { get; set; }
}

/// <summary>
/// Response for a cell's ownership history.
/// </summary>
public class CellHistoryResponse
{
    public long CellId { get; set; }
    public CellOwnerInfo? CurrentOwner { get; set; }
    public int TransferCount { get; set; }
    public List<CellTransferDetail> History { get; set; } = [];
}

public class CellOwnerInfo
{
    public Guid OwnerId { get; set; }
    public DateTime ClaimedAt { get; set; }
}

public class CellTransferDetail
{
    public Guid? FromUserId { get; set; }
    public Guid ToUserId { get; set; }
    public DateTime TransferredAt { get; set; }
    public Guid ClaimId { get; set; }
}

/// <summary>
/// Response for the user's rich public profile.
/// </summary>
public class UserProfileResponse
{
    public Guid Id { get; set; }
    public string DisplayName { get; set; } = "";
    public string Color { get; set; } = "";
    public int AvatarId { get; set; }
    public int HexCount { get; set; }
    public int Streak { get; set; }
    public int MaxStreak { get; set; }
    public double DistanceKm { get; set; }
    public int TopThreeFinishes { get; set; }
    public int TopTenFinishes { get; set; }
    public int TopHundredFinishes { get; set; }
    public int TopThousandFinishes { get; set; }
    public bool IsStreakActive { get; set; }
    public DateTime JoinedAt { get; set; }
    public int CurrentRank { get; set; }
    public int TotalPlayers { get; set; }
}

/// <summary>
/// Leaderboard entry shown in the top list.
/// </summary>
public class LeaderboardEntryResponse
{
    public int Rank { get; set; }
    public Guid UserId { get; set; }
    public string UserName { get; set; } = "";
    public string UserColor { get; set; } = "";
    public int UserAvatar { get; set; }
    public int UserHexCount { get; set; }
    public int UserStreak { get; set; }
    public double UserDistanceKm { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
}

/// <summary>
/// The requesting user's rank info (if not in top list).
/// </summary>
public class MyRankResponse
{
    public int Rank { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
}

/// <summary>
/// Full leaderboard response.
/// </summary>
public class LeaderboardResponse
{
    public List<LeaderboardEntryResponse> Top { get; set; } = [];
    public MyRankResponse? MyRank { get; set; }
    public string Scope { get; set; } = "city";
}
