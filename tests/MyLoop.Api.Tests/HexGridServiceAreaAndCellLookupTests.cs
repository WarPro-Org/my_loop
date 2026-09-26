using MyLoop.Api.Constants;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Docker-free coverage for HexGridService's pure H3 geometry surfaces (issue #73 / #69B):
/// CalculateArea and cell/neighborhood lookups. No DB, no mocks needed — these operate purely
/// on H3 index math.
/// </summary>
public class HexGridServiceAreaAndCellLookupTests
{
    private static HexGridService Service() => new(new GeoService(), TestRules.Settings);

    // Circumradius (center-to-vertex) of a regular hexagon whose area is the game's average
    // res-11 cell area: A = (3√3 / 2)·r²  ⇒  r = √(2A / (3√3)) ≈ 28.8 m for 2,150 m².
    private static readonly double AverageCellCircumradiusMeters =
        Math.Sqrt(2 * GameConstants.CellAreaSquareMeters / (3 * Math.Sqrt(3)));

    // Adjacent hexagon centers sit √3·r ≈ 49.8 m apart, so 2·r ≈ 57.5 m admits "same or
    // adjacent cell" but rejects any cell two or more rings away (≥ 3·r ≈ 86 m).
    private static readonly double MaxSameOrAdjacentCellCenterDriftMeters =
        2 * AverageCellCircumradiusMeters;

    // ── CalculateArea ────────────────────────────────────────────────────────

    [Fact]
    public void CalculateArea_of_zero_cells_is_zero()
    {
        Assert.Equal(0.0, Service().CalculateArea(0));
    }

    [Fact]
    public void CalculateArea_of_one_cell_equals_the_single_cell_constant()
    {
        Assert.Equal(GameConstants.CellAreaSquareMeters, Service().CalculateArea(1));
    }

    [Theory]
    [InlineData(5)]
    [InlineData(100)]
    [InlineData(3000)]
    public void CalculateArea_scales_linearly_with_cell_count(int cellCount)
    {
        var expected = cellCount * GameConstants.CellAreaSquareMeters;

        Assert.Equal(expected, Service().CalculateArea(cellCount));
    }

    // ── GetCellAtPoint / GetCellCenter round-trip ────────────────────────────

    [Fact]
    public void GetCellAtPoint_returns_a_boundary_with_hexagon_or_pentagon_vertex_count()
    {
        var cell = Service().GetCellAtPoint(37.7749, -122.4194);

        // H3 cells are hexagons (6 vertices) or, rarely, pentagons (5 vertices) at the 12
        // icosahedron corners; NTS returns a closed ring, so the boundary has one extra
        // point equal to the first. Anything outside {6,7} means the boundary extraction broke.
        Assert.True(cell.Boundary.Length is 6 or 7,
            $"expected 6 or 7 boundary vertices, got {cell.Boundary.Length}");
    }

    [Fact]
    public void GetCellAtPoint_is_deterministic_for_the_same_coordinate()
    {
        var svc = Service();

        var first = svc.GetCellAtPoint(12.9716, 77.5946);
        var second = svc.GetCellAtPoint(12.9716, 77.5946);

        Assert.Equal(first.CellId, second.CellId);
    }

    [Fact]
    public void GetCellAtPoint_maps_nearby_points_to_the_same_or_adjacent_cell_not_a_distant_one()
    {
        var svc = Service();

        // Two points ~1m apart must land in the same res-11 cell (edge ~29m) or, at worst,
        // an immediately adjacent one — never a cell whose center is far away.
        var cellA = svc.GetCellAtPoint(12.97160, 77.59460);
        var cellB = svc.GetCellAtPoint(12.97161, 77.59461);
        var centerA = svc.GetCellCenter(cellA.CellId);
        var centerB = svc.GetCellCenter(cellB.CellId);

        var geo = new GeoService();
        var centerDrift = geo.HaversineMeters(centerA.Lat, centerA.Lng, centerB.Lat, centerB.Lng);

        Assert.True(centerDrift < MaxSameOrAdjacentCellCenterDriftMeters,
            $"cell centers drifted {centerDrift} m for a ~1m input move " +
            $"(same-or-adjacent bound {MaxSameOrAdjacentCellCenterDriftMeters} m)");
    }

    [Fact]
    public void GetCellCenter_of_the_cell_at_a_point_is_close_to_that_point()
    {
        var svc = Service();
        var cell = svc.GetCellAtPoint(12.9716, 77.5946);

        var center = svc.GetCellCenter(cell.CellId);

        var geo = new GeoService();
        var distanceFromInputToCenter = geo.HaversineMeters(12.9716, 77.5946, center.Lat, center.Lng);

        // A point can never be farther from its own cell's center than the cell's circumradius.
        Assert.True(distanceFromInputToCenter < AverageCellCircumradiusMeters,
            $"input point is {distanceFromInputToCenter} m from its cell center " +
            $"(circumradius {AverageCellCircumradiusMeters} m)");
    }

    // ── Parent / neighborhood resolution ─────────────────────────────────────

    [Fact]
    public void GetParentCellId_is_at_the_configured_parent_resolution()
    {
        var svc = Service();
        var cell = svc.GetCellAtPoint(12.9716, 77.5946);

        var parentId = svc.GetParentCellId(cell.CellId);

        Assert.True(svc.IsValidRegionId(parentId.ToString()));
    }

    [Fact]
    public void GetNeighborhoodId_differs_from_the_parent_region_id()
    {
        // H3ParentResolution (3) and H3NeighborhoodResolution (8) are distinct resolutions —
        // a regression that collapsed them would silently break exploration bucketing.
        Assert.NotEqual(GameConstants.H3ParentResolution, GameConstants.H3NeighborhoodResolution);

        var svc = Service();
        var cell = svc.GetCellAtPoint(12.9716, 77.5946);

        var parentId = svc.GetParentCellId(cell.CellId);
        var neighborhoodId = svc.GetNeighborhoodId(cell.CellId);

        Assert.NotEqual(parentId, neighborhoodId);
    }

    [Fact]
    public void GetParentCellId_is_stable_for_points_within_the_same_region()
    {
        var svc = Service();

        var cellA = svc.GetCellAtPoint(12.9716, 77.5946);
        var cellB = svc.GetCellAtPoint(12.9717, 77.5947); // a few meters away

        Assert.Equal(svc.GetParentCellId(cellA.CellId), svc.GetParentCellId(cellB.CellId));
    }

    // ── GetNearbyNeighborhoods ────────────────────────────────────────────────

    [Fact]
    public void GetNearbyNeighborhoods_with_radius_zero_returns_only_the_center()
    {
        var svc = Service();

        var result = svc.GetNearbyNeighborhoods(12.9716, 77.5946, 0);

        Assert.Single(result);
    }

    [Fact]
    public void GetNearbyNeighborhoods_with_radius_one_includes_the_center_neighborhood()
    {
        var svc = Service();
        var centerCell = svc.GetCellAtPoint(12.9716, 77.5946);
        var centerNeighborhood = svc.GetNeighborhoodId(centerCell.CellId);

        var result = svc.GetNearbyNeighborhoods(12.9716, 77.5946, 1);

        Assert.Contains(centerNeighborhood, result);
    }

    [Fact]
    public void GetNearbyNeighborhoods_returns_more_cells_as_radius_grows()
    {
        var svc = Service();

        var radius0 = svc.GetNearbyNeighborhoods(12.9716, 77.5946, 0);
        var radius1 = svc.GetNearbyNeighborhoods(12.9716, 77.5946, 1);
        var radius2 = svc.GetNearbyNeighborhoods(12.9716, 77.5946, 2);

        Assert.True(radius1.Count > radius0.Count);
        Assert.True(radius2.Count > radius1.Count);
    }

    [Fact]
    public void GetNearbyNeighborhoods_returns_distinct_ids()
    {
        var svc = Service();

        var result = svc.GetNearbyNeighborhoods(12.9716, 77.5946, 2);

        Assert.Equal(result.Count, result.Distinct().Count());
    }

    // ── IsValidRegionId negative space (boundary/degenerate) ─────────────────

    [Theory]
    [InlineData("-1")]
    [InlineData("999999999999999999")]
    [InlineData("1.5")]
    [InlineData(" ")]
    public void IsValidRegionId_rejects_malformed_or_out_of_range_input(string input)
    {
        Assert.False(Service().IsValidRegionId(input));
    }
}
