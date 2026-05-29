using MyLoop.Api.Constants;

namespace MyLoop.Api.Services;

/// <summary>
/// Geographic math operations — distance, area, and coordinate helpers.
/// </summary>
public class GeoService : IGeoService
{
    public double HaversineMeters(double lat1, double lng1, double lat2, double lng2)
    {
        double earthRadius = GameConstants.EarthRadiusMeters;

        // Convert degree deltas to radians
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;

        // Haversine formula: square of half the chord length
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);

        // Arc length on the sphere
        return earthRadius * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }

    public double CalculatePathDistance(double[][] path)
    {
        double total = 0;
        for (int i = 1; i < path.Length; i++)
        {
            var p1 = path[i - 1];
            var p2 = path[i];
            total += HaversineMeters(p1[0], p1[1], p2[0], p2[1]);
        }
        return total;
    }

    public double CalculatePolygonArea(double[][] polygon)
    {
        if (polygon.Length < 3) return 0;

        // Use centroid as origin for local projection
        var centLat = polygon.Average(p => p[0]);
        var centLng = polygon.Average(p => p[1]);

        double metersPerDegreeLat = GameConstants.MetersPerDegreeLat;
        var metersPerDegreeLng = GameConstants.MetersPerDegreeLat * Math.Cos(centLat * Math.PI / 180.0);

        // Shoelace formula in metric coordinates
        double area = 0;
        for (int i = 0; i < polygon.Length; i++)
        {
            var j = (i + 1) % polygon.Length;
            var xi = (polygon[i][1] - centLng) * metersPerDegreeLng;
            var yi = (polygon[i][0] - centLat) * metersPerDegreeLat;
            var xj = (polygon[j][1] - centLng) * metersPerDegreeLng;
            var yj = (polygon[j][0] - centLat) * metersPerDegreeLat;
            area += xi * yj - xj * yi;
        }
        return Math.Abs(area) / 2.0;
    }
}
