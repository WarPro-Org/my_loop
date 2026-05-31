namespace MyLoop.Api.Models;

/// <summary>
/// Result of a walk-through trail claim — returns newly claimed hex boundaries
/// for immediate rendering on the client map.
/// </summary>
public class TrailClaimResult
{
    public bool Success { get; init; }
    public string? Error { get; init; }
    public TrailClaimResponse? Data { get; init; }

    public static TrailClaimResult Failure(string error) => new() { Success = false, Error = error };
    public static TrailClaimResult Succeeded(TrailClaimResponse data) => new() { Success = true, Data = data };
}

public class TrailClaimResponse
{
    /// <summary>Newly claimed hex boundaries (polygons to render on map).</summary>
    public List<TrailHexResponse> ClaimedCells { get; set; } = [];

    /// <summary>Total hexes claimed in this batch (includes stolen).</summary>
    public int NewCellCount { get; set; }

    /// <summary>Hexes stolen from other players in this batch.</summary>
    public int StolenCount { get; set; }
}

public class TrailHexResponse
{
    public long CellId { get; set; }
    public double[][] Boundary { get; set; } = [];
    public bool WasStolen { get; set; }
    public string? PreviousOwnerName { get; set; }
}

/// <summary>
/// Response for a single-point step claim.
/// Null/empty response means the user is still in the same hex (no new claim).
/// </summary>
public class StepClaimResponse
{
    /// <summary>True if a new hex was claimed.</summary>
    public bool Claimed { get; set; }

    /// <summary>The H3 cell ID that was claimed.</summary>
    public long CellId { get; set; }

    /// <summary>Polygon boundary for rendering on the map.</summary>
    public double[][] Boundary { get; set; } = [];

    /// <summary>True if this hex was stolen from another player.</summary>
    public bool WasStolen { get; set; }

    /// <summary>Name of the previous owner (if stolen).</summary>
    public string? PreviousOwnerName { get; set; }
}
