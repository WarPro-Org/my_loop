namespace MyLoop.Api.Models;

/// <summary>
/// Represents a single hex cell with its ID and boundary polygon.
/// Used instead of tuple syntax for clarity.
/// </summary>
public class HexCell
{
    public long CellId { get; set; }
    public double[][] Boundary { get; set; } = [];
}

/// <summary>
/// The hexes captured by a path plus the authoritative number of distinct
/// loops the path encloses — area-validated and de-duplicated the same way the
/// server fills them, so it is the count the user should see (issue #21).
/// </summary>
public record CapturedTerritory(List<HexCell> Cells, int LoopCount);
