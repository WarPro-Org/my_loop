namespace MyLoop.Api.Entities;

/// <summary>
/// Records that a user has ever visited a specific hex cell.
/// Persists even if the cell decays or is stolen — used for exploration % tracking.
/// One row per (UserId, CellId) pair — permanently records discovery.
/// </summary>
public class ExploredCell
{
    public Guid UserId { get; set; }
    public long CellId { get; set; }

    /// <summary>
    /// H3 parent cell at resolution 8 (~700m neighborhood).
    /// Used for fast exploration % queries: count cells per neighborhood.
    /// </summary>
    public long NeighborhoodId { get; set; }

    /// <summary>When the user first walked through this hex.</summary>
    public DateTime FirstVisitedAt { get; set; }

    public User? User { get; set; }
}
