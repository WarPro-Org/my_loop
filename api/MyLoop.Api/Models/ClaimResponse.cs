namespace MyLoop.Api.Models;

public class ClaimResponse
{
    public Guid Id { get; set; }

    /// <summary>
    /// Total hexes enclosed by the claimed loop (trail + filled interior). Includes cells
    /// the user already owned, so this is NOT the number newly added by this claim.
    /// </summary>
    public int CellCount { get; set; }

    /// <summary>
    /// Hexes this claim newly assigned to the user (new captures + steals), EXCLUDING cells
    /// the user already owned (e.g. trail hexes claimed live via batch-step during the walk).
    /// This is the count the client should add on top of its live count for the capture
    /// celebration — using <see cref="CellCount"/> double-counts the trail hexes (#55).
    /// </summary>
    public int NewlyClaimedCount { get; set; }

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
