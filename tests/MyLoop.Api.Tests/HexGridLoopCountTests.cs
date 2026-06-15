using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Tests the AUTHORITATIVE loop count surfaced to the app (issue #21). Loops are
/// counted only after area-validation and de-duplication — not as raw proximity
/// closures — so out-and-back paths and sub-threshold wiggles that previously
/// inflated the client count now correctly report zero.
/// </summary>
public class HexGridLoopCountTests
{
    private static HexGridService Service() => new(new GeoService());

    // Rough meters-per-degree near the equator — enough to size test loops
    // relative to GameConstants.MinFillAreaSquareMeters (5,000 m²).
    private const double MPerDegLat = 110574.0;
    private const double MPerDegLng = 111320.0;

    /// <summary>
    /// A closed square loop of side ~<paramref name="sideMeters"/>, sampled with
    /// <paramref name="pointsPerSide"/> points per side and a final point equal
    /// to the first so the path closes.
    /// </summary>
    private static double[][] Square(double sideMeters, int pointsPerSide)
    {
        var dLat = sideMeters / MPerDegLat;
        var dLng = sideMeters / MPerDegLng;
        var corners = new (double Lat, double Lng)[]
        {
            (0.0, 0.0),
            (0.0, dLng),
            (dLat, dLng),
            (dLat, 0.0),
            (0.0, 0.0),
        };

        var pts = new List<double[]>();
        for (int c = 0; c < corners.Length - 1; c++)
        {
            var (lat0, lng0) = corners[c];
            var (lat1, lng1) = corners[c + 1];
            for (int i = 0; i < pointsPerSide; i++)
            {
                var t = (double)i / pointsPerSide;
                pts.Add([lat0 + (lat1 - lat0) * t, lng0 + (lng1 - lng0) * t]);
            }
        }
        pts.Add([corners[^1].Lat, corners[^1].Lng]);
        return pts.ToArray();
    }

    [Fact]
    public void Real_loop_counts_as_one()
    {
        // ~100m square ≈ 10,000 m² > 5,000 m² threshold → a genuine loop.
        var territory = Service().ComputeCapturedTerritory(Square(100, 8));
        Assert.Equal(1, territory.LoopCount);
    }

    [Fact]
    public void Out_and_back_path_counts_as_zero()
    {
        // North then back south along the same line: proximity closures exist,
        // but the enclosed area is ~0 → filtered out (the core #21 over-count).
        var dLat = 5.0 / MPerDegLat; // ~5m steps
        var pts = new List<double[]>();
        for (int i = 0; i < 25; i++) pts.Add([i * dLat, 0.0]);
        for (int i = 24; i >= 0; i--) pts.Add([i * dLat, 0.0]);

        var territory = Service().ComputeCapturedTerritory(pts.ToArray());
        Assert.Equal(0, territory.LoopCount);
    }

    [Fact]
    public void Tiny_loop_below_area_threshold_counts_as_zero()
    {
        // ~30m square ≈ 900 m² < 5,000 m² → below the fill-area threshold.
        var territory = Service().ComputeCapturedTerritory(Square(30, 8));
        Assert.Equal(0, territory.LoopCount);
    }
}
