namespace MyLoop.Api.Entities;

using System.Text.Json;

/// A claim is one completed loop. The user walked a path, closed it,
/// and submitted it. The server then computed which hexes fall inside
/// that loop and assigned them to the user.
public class Claim
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public int CellCount { get; set; } // how many hexes this claim captured
    public double AreaM2 { get; set; } // total area in square meters
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // The original polygon the user walked, stored as JSON: "[[lat,lng],[lat,lng],...]"
    public string PolygonJson { get; set; } = "[]";

    public double[][] GetPolygon() => JsonSerializer.Deserialize<double[][]>(PolygonJson)!;
    public void SetPolygon(double[][] polygon) => PolygonJson = JsonSerializer.Serialize(polygon);

    public User? User { get; set; }
}
