namespace MyLoop.Api.Models;

public class ClaimResponse
{
    public Guid Id { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
    public int StolenFromOthers { get; set; }
    public List<double[][]> Boundaries { get; set; } = [];
}

public class ClaimHistoryEntry
{
    public Guid ClaimId { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
    public DateTime Date { get; set; }
}
