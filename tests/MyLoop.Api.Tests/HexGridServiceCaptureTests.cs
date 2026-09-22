using MyLoop.Api.Constants;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Docker-free coverage for HexGridService's trail-cell and captured-territory computation
/// (issue #73 / #69B) — the surface that converts a raw GPS path into the hexes a claim
/// actually awards. Targets degenerate paths (empty, single-point, stationary duplicates) that
/// a flaky GPS receiver or a malicious client can realistically send.
/// </summary>
public class HexGridServiceCaptureTests
{
    private static HexGridService Service() => new(new GeoService());

    private const double MPerDegLat = 110574.0;
    private const double MPerDegLng = 111320.0;

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

    // ── Empty / single-point paths ───────────────────────────────────────────

    [Fact]
    public void GetTrailCells_of_empty_path_is_empty()
    {
        Assert.Empty(Service().GetTrailCells([]));
    }

    [Fact]
    public void ComputeCapturedTerritory_of_empty_path_has_no_cells_and_no_loops()
    {
        var territory = Service().ComputeCapturedTerritory([]);

        Assert.Empty(territory.Cells);
        Assert.Equal(0, territory.LoopCount);
    }

    [Fact]
    public void GetTrailCells_of_a_single_point_is_exactly_one_cell()
    {
        var cells = Service().GetTrailCells([[12.9716, 77.5946]]);

        Assert.Single(cells);
    }

    [Fact]
    public void ComputeCapturedCells_of_a_single_point_matches_GetTrailCells()
    {
        double[][] path = [[12.9716, 77.5946]];
        var svc = Service();

        var captured = svc.ComputeCapturedCells(path);
        var trail = svc.GetTrailCells(path);

        Assert.Equal(trail.Select(c => c.CellId).ToHashSet(), captured.Select(c => c.CellId).ToHashSet());
    }

    // ── Stationary / duplicate-point paths ───────────────────────────────────

    [Fact]
    public void GetTrailCells_deduplicates_stationary_duplicate_points_to_one_cell()
    {
        // A player standing still can produce many identical GPS fixes in a row (or a malicious
        // client can replay one fix MinLoopPoints times) — the trail must not report a cell per
        // sample.
        var path = new double[GameConstants.MinLoopPoints][];
        for (var i = 0; i < path.Length; i++)
            path[i] = [12.9716, 77.5946];

        var cells = Service().GetTrailCells(path);

        Assert.Single(cells);
    }

    [Fact]
    public void Stationary_duplicate_points_do_not_count_as_a_captured_loop()
    {
        // Even though duplicate points trivially satisfy the closure-distance check (distance
        // 0), a zero-area "loop" must be filtered by the fill-area threshold and award no
        // fill — only the one trail cell the player is standing on.
        var path = new double[GameConstants.MinLoopPoints][];
        for (var i = 0; i < path.Length; i++)
            path[i] = [12.9716, 77.5946];

        var territory = Service().ComputeCapturedTerritory(path);

        Assert.Equal(0, territory.LoopCount);
        Assert.Single(territory.Cells);
    }

    // ── Paths too short to form a loop ────────────────────────────────────────

    [Fact]
    public void A_short_path_below_the_loop_minimum_captures_only_trail_cells()
    {
        // Five widely-spaced points — well under MinLoopPoints — can never enclose an area no
        // matter how they're arranged.
        double[][] path =
        [
            [12.9700, 77.5900],
            [12.9750, 77.5950],
            [12.9800, 77.6000],
            [12.9750, 77.6050],
            [12.9700, 77.6000],
        ];
        Assert.True(path.Length < GameConstants.MinLoopPoints);

        var svc = Service();
        var territory = svc.ComputeCapturedTerritory(path);
        var trail = svc.GetTrailCells(path);

        Assert.Equal(0, territory.LoopCount);
        Assert.Equal(trail.Select(c => c.CellId).ToHashSet(), territory.Cells.Select(c => c.CellId).ToHashSet());
    }

    // ── A real closed loop fills its interior ────────────────────────────────

    [Fact]
    public void A_real_closed_loop_captures_more_cells_than_its_trail_alone()
    {
        // ~100m square, well above MinFillAreaSquareMeters — the interior fill must add cells
        // beyond the ones the trail itself crosses.
        var path = Square(100, 8);
        var svc = Service();

        var territory = svc.ComputeCapturedTerritory(path);
        var trailOnly = svc.GetTrailCells(path);

        Assert.Equal(1, territory.LoopCount);
        Assert.True(territory.Cells.Count > trailOnly.Count,
            $"expected fill to add cells beyond the {trailOnly.Count} trail cells, got {territory.Cells.Count}");
    }

    [Fact]
    public void ComputeCapturedCells_and_ComputeCapturedTerritory_agree_on_the_cell_set()
    {
        var path = Square(100, 8);
        var svc = Service();

        var cells = svc.ComputeCapturedCells(path);
        var territory = svc.ComputeCapturedTerritory(path);

        Assert.Equal(
            territory.Cells.Select(c => c.CellId).ToHashSet(),
            cells.Select(c => c.CellId).ToHashSet());
    }

    [Fact]
    public void Every_captured_cell_has_a_non_empty_boundary()
    {
        var path = Square(100, 8);

        var cells = Service().ComputeCapturedCells(path);

        Assert.NotEmpty(cells);
        Assert.All(cells, c => Assert.NotEmpty(c.Boundary));
    }

    [Fact]
    public void Captured_cells_have_no_duplicate_cell_ids()
    {
        var path = Square(100, 8);

        var cells = Service().ComputeCapturedCells(path);

        Assert.Equal(cells.Count, cells.Select(c => c.CellId).Distinct().Count());
    }
}
