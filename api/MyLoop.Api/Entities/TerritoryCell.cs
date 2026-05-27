namespace MyLoop.Api.Entities;

using System.Text.Json;

/// A single territory cell on the map. Each cell is a hexagon (~65m wide).
/// The cell_id is an H3 index (64-bit integer) that uniquely identifies a hex on Earth.
/// Whoever owns the cell, owns that piece of land.
public class TerritoryCell
{
    public long CellId { get; set; } // H3 index — the unique ID of this hex on the planet
    public Guid OwnerId { get; set; } // who currently owns this hex
    public Guid ClaimId { get; set; } // which claim captured this hex
    public DateTime ClaimedAt { get; set; }

    // The 6 corner points of this hex stored as JSON string: "[[lat,lng],[lat,lng],...]"
    public string BoundaryJson { get; set; } = "[]";

    public double[][] GetBoundary() => JsonSerializer.Deserialize<double[][]>(BoundaryJson)!;
    public void SetBoundary(double[][] boundary) => BoundaryJson = JsonSerializer.Serialize(boundary);

    public User? Owner { get; set; }
    public Claim? Claim { get; set; }
}
