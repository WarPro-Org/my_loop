namespace MyLoop.Api.Entities;

using System.Text.Json;

/// <summary>
/// Represents a single completed territory claim — one loop submission by a user.
/// When a player walks a path and submits it, the server computes the enclosed area
/// and records this claim along with the original polygon and resulting statistics.
/// A claim is immutable once created; territory ownership changes are tracked in <see cref="TerritoryCell"/>.
/// </summary>
public class Claim
{
    /// <summary>Unique identifier for this claim (primary key).</summary>
    public Guid Id { get; set; }

    /// <summary>The user who made this claim.</summary>
    public Guid UserId { get; set; }

    /// <summary>Number of H3 hexagonal cells captured by this claim.</summary>
    public int CellCount { get; set; }

    /// <summary>Total area captured in square meters (CellCount × average cell area).</summary>
    public double AreaM2 { get; set; }

    /// <summary>Timestamp when the claim was submitted (defaults to UTC now).</summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// The original GPS polygon the user walked, serialized as a JSON array of [lat, lng] pairs.
    /// Stored as a string for simple persistence without requiring PostGIS geometry columns.
    /// </summary>
    public string PolygonJson { get; set; } = "[]";

    /// <summary>
    /// Deserializes the stored polygon JSON back into a coordinate array.
    /// </summary>
    /// <returns>Array of [latitude, longitude] coordinate pairs.</returns>
    public double[][] GetPolygon() => JsonSerializer.Deserialize<double[][]>(PolygonJson)!;

    /// <summary>
    /// Serializes a coordinate array into JSON and stores it in <see cref="PolygonJson"/>.
    /// </summary>
    /// <param name="polygon">Array of [latitude, longitude] coordinate pairs to store.</param>
    public void SetPolygon(double[][] polygon) => PolygonJson = JsonSerializer.Serialize(polygon);

    /// <summary>
    /// Appends GPS points to the stored walk path, keeping at most <paramref name="maxPoints"/>
    /// (most recent retained). Because one walk now folds into a single Claim (#56), each batch
    /// accumulates its slice here so the Claim retains the whole walk's geometry for anti-cheat
    /// forensics — not just its first batch — while the cap bounds row growth on long walks.
    /// </summary>
    public void AppendToPolygon(double[][] morePoints, int maxPoints)
    {
        if (morePoints.Length == 0) return;
        var existing = GetPolygon();
        var combined = existing.Length == 0 ? morePoints : [.. existing, .. morePoints];
        if (combined.Length > maxPoints)
            combined = combined[^maxPoints..];
        SetPolygon(combined);
    }

    /// <summary>Navigation property to the user who submitted this claim.</summary>
    public User? User { get; set; }
}
