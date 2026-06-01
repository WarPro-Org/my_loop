using MyLoop.Api.Models;

namespace MyLoop.Api.Interfaces;

/// <summary>
/// Geographic math operations — distance, area, and coordinate helpers.
/// </summary>
public interface IGeoService
{
    /// <summary>
    /// Calculates the great-circle distance between two points using Haversine.
    /// </summary>
    double HaversineMeters(double lat1, double lng1, double lat2, double lng2);

    /// <summary>
    /// Calculates the total distance of a GPS path in meters.
    /// </summary>
    double CalculatePathDistance(double[][] path);

    /// <summary>
    /// Calculates the approximate area of a geographic polygon in square meters.
    /// Uses the Shoelace formula with local metric projection.
    /// </summary>
    double CalculatePolygonArea(double[][] polygon);
}
