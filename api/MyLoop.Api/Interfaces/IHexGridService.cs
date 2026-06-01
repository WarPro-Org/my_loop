using MyLoop.Api.Models;

namespace MyLoop.Api.Interfaces;

/// <summary>
/// Hex grid operations — converts GPS data into H3 hex cells.
/// </summary>
public interface IHexGridService
{
    /// <summary>
    /// Computes all hexagonal cells captured by the user's walked path.
    /// Trail cells (along the path) + fill cells (inside closed loops).
    /// </summary>
    List<HexCell> ComputeCapturedCells(double[][] path);

    /// <summary>
    /// Gets the center coordinate of an H3 cell.
    /// </summary>
    GeoCoordinate GetCellCenter(long cellId);

    /// <summary>
    /// Gets the H3 parent cell ID at the parent resolution for spatial bucketing.
    /// </summary>
    long GetParentCellId(long cellId);

    /// <summary>
    /// Gets the H3 parent cell ID at resolution 8 (~700m neighborhood).
    /// Used for exploration % bucketing.
    /// </summary>
    long GetNeighborhoodId(long cellId);

    /// <summary>
    /// Calculates the total area for a given number of hex cells.
    /// </summary>
    double CalculateArea(int cellCount);

    /// <summary>
    /// Returns true if the path contains at least one closed loop
    /// (self-intersection within closure distance).
    /// </summary>
    bool HasClosedLoop(double[][] path);

    /// <summary>
    /// Computes only the trail cells — hexes the GPS points physically fall on.
    /// No loop detection or interior fill. Used for walk-through claiming.
    /// </summary>
    List<HexCell> GetTrailCells(double[][] points);

    /// <summary>
    /// Gets the single H3 hex cell for a GPS coordinate.
    /// Returns the cell ID and boundary polygon.
    /// </summary>
    HexCell GetCellAtPoint(double lat, double lng);

    /// <summary>
    /// Gets neighborhood IDs (res 8) within radius k of the given GPS point.
    /// Returns the center neighborhood + ring-k neighbors.
    /// </summary>
    List<long> GetNearbyNeighborhoods(double lat, double lng, int k = 1);
}
