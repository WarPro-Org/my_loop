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
