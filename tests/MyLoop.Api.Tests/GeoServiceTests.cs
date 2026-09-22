using MyLoop.Api.Constants;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Pure-math coverage for GeoService — Haversine distance, path distance, and the shoelace
/// polygon area. Docker-free (issue #73 / #69B): no DB, no H3, just floating-point geometry.
/// These are MyLoop's highest bug-class ROI surface — a sign error or a degrees/radians mix-up
/// here silently corrupts every claim's distance and area gating.
/// </summary>
public class GeoServiceTests
{
    private static readonly GeoService Geo = new();

    // ── HaversineMeters ──────────────────────────────────────────────────────

    [Fact]
    public void HaversineMeters_is_zero_for_identical_points()
    {
        Assert.Equal(0.0, Geo.HaversineMeters(12.9716, 77.5946, 12.9716, 77.5946));
    }

    [Theory]
    [InlineData(0.0, 0.0)]
    [InlineData(37.7749, -122.4194)]
    [InlineData(-33.8688, 151.2093)]
    [InlineData(89.9, 45.0)]
    public void HaversineMeters_is_zero_for_identical_points_at_various_locations(double lat, double lng)
    {
        Assert.Equal(0.0, Geo.HaversineMeters(lat, lng, lat, lng));
    }

    [Fact]
    public void HaversineMeters_is_symmetric()
    {
        var forward = Geo.HaversineMeters(12.9716, 77.5946, 13.0827, 80.2707);
        var backward = Geo.HaversineMeters(13.0827, 80.2707, 12.9716, 77.5946);

        Assert.Equal(forward, backward, precision: 9);
    }

    [Fact]
    public void HaversineMeters_matches_hand_computed_value_for_one_degree_of_longitude_on_the_equator()
    {
        // On the equator, a great-circle arc along a line of constant latitude IS a great
        // circle, so the distance for 1 degree of longitude is exactly R * (pi/180).
        var expected = GameConstants.EarthRadiusMeters * Math.PI / 180.0;

        var actual = Geo.HaversineMeters(0.0, 0.0, 0.0, 1.0);

        Assert.Equal(expected, actual, precision: 3);
    }

    [Fact]
    public void HaversineMeters_matches_hand_computed_value_for_a_quarter_of_the_equator()
    {
        // 90 degrees of longitude on the equator is a quarter of the Earth's circumference.
        var expected = GameConstants.EarthRadiusMeters * Math.PI / 2.0;

        var actual = Geo.HaversineMeters(0.0, 0.0, 0.0, 90.0);

        Assert.Equal(expected, actual, precision: 2);
    }

    [Fact]
    public void HaversineMeters_of_antipodal_points_is_half_the_earths_circumference()
    {
        // (0,0) and (0,180) are antipodal along the equator — the great-circle distance is
        // exactly half the circumference (pi * R), the longest possible Haversine result.
        var expected = GameConstants.EarthRadiusMeters * Math.PI;

        var actual = Geo.HaversineMeters(0.0, 0.0, 0.0, 180.0);

        Assert.Equal(expected, actual, precision: 2);
    }

    [Fact]
    public void HaversineMeters_of_pole_to_pole_antipodal_points_is_half_the_earths_circumference()
    {
        // The north and south poles are antipodal via any meridian — same expected distance
        // as the equatorial antipodal case, exercising the latitude-extreme branch instead.
        var expected = GameConstants.EarthRadiusMeters * Math.PI;

        var actual = Geo.HaversineMeters(90.0, 0.0, -90.0, 0.0);

        Assert.Equal(expected, actual, precision: 2);
    }

    [Fact]
    public void HaversineMeters_is_never_negative()
    {
        var distance = Geo.HaversineMeters(51.5074, -0.1278, -33.8688, 151.2093);

        Assert.True(distance > 0);
    }

    // ── CalculatePathDistance ────────────────────────────────────────────────

    [Fact]
    public void CalculatePathDistance_of_empty_path_is_zero()
    {
        Assert.Equal(0.0, Geo.CalculatePathDistance([]));
    }

    [Fact]
    public void CalculatePathDistance_of_single_point_is_zero()
    {
        Assert.Equal(0.0, Geo.CalculatePathDistance([[12.9716, 77.5946]]));
    }

    [Fact]
    public void CalculatePathDistance_of_stationary_duplicate_points_is_zero()
    {
        // GPS sometimes reports the same fix repeatedly for a stationary player — the total
        // walked distance must not inflate from that.
        double[][] path = [[12.9716, 77.5946], [12.9716, 77.5946], [12.9716, 77.5946]];

        Assert.Equal(0.0, Geo.CalculatePathDistance(path));
    }

    [Fact]
    public void CalculatePathDistance_equals_the_sum_of_individual_leg_distances()
    {
        double[][] path =
        [
            [12.9716, 77.5946],
            [12.9800, 77.6000],
            [12.9900, 77.6100],
        ];

        var leg1 = Geo.HaversineMeters(path[0][0], path[0][1], path[1][0], path[1][1]);
        var leg2 = Geo.HaversineMeters(path[1][0], path[1][1], path[2][0], path[2][1]);

        var total = Geo.CalculatePathDistance(path);

        Assert.Equal(leg1 + leg2, total, precision: 9);
    }

    [Fact]
    public void CalculatePathDistance_of_a_round_trip_is_twice_the_one_way_distance()
    {
        double[][] outbound = [[0.0, 0.0], [0.0, 0.01], [0.0, 0.02]];
        double[][] roundTrip = [[0.0, 0.0], [0.0, 0.01], [0.0, 0.02], [0.0, 0.01], [0.0, 0.0]];

        var outboundDistance = Geo.CalculatePathDistance(outbound);
        var roundTripDistance = Geo.CalculatePathDistance(roundTrip);

        Assert.Equal(outboundDistance * 2.0, roundTripDistance, precision: 6);
    }

    // ── CalculatePolygonArea ─────────────────────────────────────────────────

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    public void CalculatePolygonArea_below_three_vertices_is_zero(int vertexCount)
    {
        var polygon = new double[vertexCount][];
        for (var i = 0; i < vertexCount; i++)
            polygon[i] = [12.9716 + i * 0.0001, 77.5946];

        Assert.Equal(0.0, Geo.CalculatePolygonArea(polygon));
    }

    [Fact]
    public void CalculatePolygonArea_is_never_negative()
    {
        // A clockwise-wound triangle produces a negative raw shoelace sum before Abs() —
        // regression guard against dropping the Math.Abs and returning a signed area.
        double[][] clockwiseTriangle = [[0.0, 0.0], [0.001, 0.0], [0.0, 0.001]];

        var area = Geo.CalculatePolygonArea(clockwiseTriangle);

        Assert.True(area > 0);
    }

    [Fact]
    public void CalculatePolygonArea_matches_hand_computed_value_for_a_small_equatorial_square()
    {
        // Near the equator, 1 degree of latitude and longitude are both ~111,320 m
        // (GameConstants.MetersPerDegreeLat), so a 0.001-degree square is ~111.32 m per side.
        const double sideDeg = 0.001;
        double[][] square =
        [
            [0.0, 0.0],
            [0.0, sideDeg],
            [sideDeg, sideDeg],
            [sideDeg, 0.0],
        ];

        var sideMeters = GameConstants.MetersPerDegreeLat * sideDeg;
        var expected = sideMeters * sideMeters;

        var actual = Geo.CalculatePolygonArea(square);

        // Within 1%: longitude scaling uses cos(centroid latitude), not the pole-to-pole
        // constant, so a tiny deviation from a perfect square is expected even at the equator.
        Assert.True(Math.Abs(actual - expected) / expected < 0.01,
            $"expected ~{expected} m^2, got {actual} m^2");
    }

    [Fact]
    public void CalculatePolygonArea_is_independent_of_winding_order()
    {
        double[][] clockwise = [[0.0, 0.0], [0.001, 0.0], [0.001, 0.001], [0.0, 0.001]];
        double[][] counterClockwise = [[0.0, 0.0], [0.0, 0.001], [0.001, 0.001], [0.001, 0.0]];

        var clockwiseArea = Geo.CalculatePolygonArea(clockwise);
        var counterClockwiseArea = Geo.CalculatePolygonArea(counterClockwise);

        Assert.Equal(clockwiseArea, counterClockwiseArea, precision: 6);
    }

    [Fact]
    public void CalculatePolygonArea_is_independent_of_starting_vertex()
    {
        double[][] fromCorner0 = [[0.0, 0.0], [0.001, 0.0], [0.001, 0.001], [0.0, 0.001]];
        double[][] fromCorner2 = [[0.001, 0.001], [0.0, 0.001], [0.0, 0.0], [0.001, 0.0]];

        var area0 = Geo.CalculatePolygonArea(fromCorner0);
        var area2 = Geo.CalculatePolygonArea(fromCorner2);

        Assert.Equal(area0, area2, precision: 6);
    }

    [Fact]
    public void CalculatePolygonArea_of_a_self_intersecting_bowtie_uses_the_raw_signed_sum()
    {
        // The shoelace formula alone (no polygon repair — that lives in HexGridService's
        // BuildRepairedPolygon) does NOT compute the true non-overlapping area of a
        // self-intersecting bowtie: this specific figure-8 vertex order makes the two lobes'
        // signed contributions cancel EXACTLY, reporting zero area for a shape that visibly
        // covers ground. This pins down that known, current behavior so a future
        // "improvement" that silently changes it is caught rather than shipped unnoticed.
        double[][] bowtie = [[0.0, 0.0], [0.001, 0.001], [0.001, 0.0], [0.0, 0.001]];

        var bowtieArea = Geo.CalculatePolygonArea(bowtie);

        double[][] simpleSquare = [[0.0, 0.0], [0.001, 0.0], [0.001, 0.001], [0.0, 0.001]];
        var squareArea = Geo.CalculatePolygonArea(simpleSquare);

        Assert.Equal(0.0, bowtieArea, precision: 6);
        Assert.True(squareArea > 0);
    }

    [Fact]
    public void CalculatePolygonArea_of_a_degenerate_zero_width_polygon_is_zero()
    {
        // All points collinear — no enclosed area regardless of vertex count.
        double[][] collinear = [[0.0, 0.0], [0.0, 0.001], [0.0, 0.002], [0.0, 0.0015]];

        var area = Geo.CalculatePolygonArea(collinear);

        Assert.Equal(0.0, area, precision: 6);
    }
}
