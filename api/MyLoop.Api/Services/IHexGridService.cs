using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

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
    /// Calculates the total area for a given number of hex cells.
    /// </summary>
    double CalculateArea(int cellCount);
}
