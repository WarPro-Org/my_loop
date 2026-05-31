namespace MyLoop.Api.Models;

public class TerritoryCellResponse
{
    public long CellId { get; set; }
    public double[][]? Boundary { get; set; }
    public Guid OwnerId { get; set; }
    public string? OwnerColor { get; set; }
    public string? OwnerName { get; set; }
    public DateTime? CooldownExpiresAtUtc { get; set; }
    public long ParentCellId { get; set; }
}

public class TerritoryStatsResponse
{
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
}

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
