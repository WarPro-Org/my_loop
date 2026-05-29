namespace MyLoop.Api.Models;

/// <summary>
/// A geographic coordinate (latitude + longitude).
/// Used instead of tuple syntax for clarity.
/// </summary>
public class GeoCoordinate
{
    public double Lat { get; set; }
    public double Lng { get; set; }
}
