namespace MyLoop.Api.Tests;

/// <summary>
/// Shared synthetic-path builders for the Docker-free HexGridService tests, so the
/// degree↔meter conversion and the square-walk shape live in one place.
/// </summary>
internal static class TestGeometry
{
    // WGS-84 meters per degree at the equator. The squares are built at (0, 0), where these
    // are accurate; they are test-only approximations and deliberately not GameConstants.
    internal const double MetersPerDegreeLatAtEquator = 110_574.0;
    internal const double MetersPerDegreeLngAtEquator = 111_320.0;

    /// <summary>
    /// A closed square walk anchored at (0, 0): <paramref name="pointsPerSide"/> evenly spaced
    /// points per side, plus a final point equal to the first so the path ends where it began.
    /// </summary>
    internal static double[][] Square(double sideMeters, int pointsPerSide)
    {
        var dLat = sideMeters / MetersPerDegreeLatAtEquator;
        var dLng = sideMeters / MetersPerDegreeLngAtEquator;
        var corners = new (double Lat, double Lng)[]
        {
            (0.0, 0.0),
            (0.0, dLng),
            (dLat, dLng),
            (dLat, 0.0),
            (0.0, 0.0),
        };

        var pts = new List<double[]>();
        for (var c = 0; c < corners.Length - 1; c++)
        {
            var (lat0, lng0) = corners[c];
            var (lat1, lng1) = corners[c + 1];
            for (var i = 0; i < pointsPerSide; i++)
            {
                var t = (double)i / pointsPerSide;
                pts.Add([lat0 + (lat1 - lat0) * t, lng0 + (lng1 - lng0) * t]);
            }
        }
        pts.Add([corners[^1].Lat, corners[^1].Lng]);
        return pts.ToArray();
    }
}
