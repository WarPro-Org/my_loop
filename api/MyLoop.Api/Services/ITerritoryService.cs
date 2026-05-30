using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// Territory operations — claim processing, territory queries, stolen cells.
/// </summary>
public interface ITerritoryService
{
    /// <summary>
    /// Processes a territory claim: validates the path, computes hex cells,
    /// assigns ownership, and records transfers.
    /// Returns the claim result or an error message.
    /// </summary>
    Task<ClaimResult> ProcessClaim(Guid userId, double[][] path);

    /// <summary>
    /// Gets all territory cells within a map viewport bounding box.
    /// </summary>
    Task<List<TerritoryCellResponse>> GetTerritoriesInViewport(
        double minLat, double minLng, double maxLat, double maxLng);

    /// <summary>
    /// Gets a user's total territory stats (cell count + area).
    /// </summary>
    Task<TerritoryStatsResponse> GetUserStats(Guid userId);

    /// <summary>
    /// Gets hexes stolen from a user within the given number of days.
    /// </summary>
    Task<StolenCellsResponse> GetStolenCells(Guid userId, int days);

    /// <summary>
    /// Gets the ownership history of a specific hex cell.
    /// </summary>
    Task<CellHistoryResponse> GetCellHistory(long cellId);

    /// <summary>
    /// Gets ALL territory cells owned by a specific user (regardless of viewport).
    /// </summary>
    Task<List<TerritoryCellResponse>> GetUserTerritories(Guid userId);

    /// <summary>
    /// Gets a user's claim history — one entry per claim submission.
    /// </summary>
    Task<List<ClaimHistoryEntry>> GetClaimHistory(Guid userId);
}

/// <summary>
/// Result of a claim operation — either success (with data) or failure (with error).
/// </summary>
public class ClaimResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public ClaimResponse? Data { get; set; }
}
