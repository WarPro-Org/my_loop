using Moq;
using MyLoop.Api.Constants;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Boundary and degenerate-input coverage for HasClosedLoop (issue #73 / #69B), the anti-cheat
/// gate that decides whether a submitted GPS path counts as a claimable loop at all.
/// <see cref="HexGridLoopClosureEquivalenceTests"/> already proves the spatial-hash scan matches
/// brute force over random walks; this file targets the inputs an attacker or a buggy client is
/// most likely to send, and pins the exact "&lt;=" closure-distance boundary using a mocked
/// <see cref="IGeoService"/> so the assertion isn't at the mercy of floating-point geometry.
/// </summary>
public class HexGridServiceHasClosedLoopBoundaryTests
{
    private static HexGridService Service() => new(new GeoService());

    // ── Degenerate inputs (guarded by the length check, before any geo math runs) ────

    [Fact]
    public void Empty_path_has_no_closed_loop()
    {
        Assert.False(Service().HasClosedLoop([]));
    }

    [Fact]
    public void Single_point_path_has_no_closed_loop()
    {
        Assert.False(Service().HasClosedLoop([[12.9716, 77.5946]]));
    }

    [Fact]
    public void Path_one_point_short_of_the_minimum_has_no_closed_loop()
    {
        var path = new double[GameConstants.MinLoopPoints - 1][];
        for (var i = 0; i < path.Length; i++)
            path[i] = [12.9716, 77.5946]; // all identical — would trivially close if length allowed it

        Assert.False(Service().HasClosedLoop(path));
    }

    [Fact]
    public void Path_at_exactly_the_minimum_length_with_identical_points_closes()
    {
        var path = new double[GameConstants.MinLoopPoints][];
        for (var i = 0; i < path.Length; i++)
            path[i] = [12.9716, 77.5946];

        Assert.True(Service().HasClosedLoop(path));
    }

    // ── Exact "<=" boundary at LoopClosureDistanceMeters, via a mocked IGeoService ────
    // HasClosedLoop has TWO "<=" comparisons: the spatial-hash scan over (i, j) pairs at least
    // MinLoopPoints apart, and the endpoint fallback IsLoopClosed(path[0], path[^1]). Each needs
    // its own boundary test, because a path that satisfies one can bypass the other.

    // Scan boundary. The path has MinLoopPoints + 2 points so exactly one scan pair qualifies
    // at the threshold — (path[MinLoopPoints], path[0]) — while the endpoint pair
    // (path[0], path[^1]) is a DIFFERENT pair that the mock reports as far. So only the scan's
    // comparison can return true. With MinLoopPoints + 1 points the endpoint pair and the scan
    // pair would coincide and the fallback would mask a broken scan comparison.
    // Points are ~0.011 m apart so every one lands in the same spatial-hash bucket (the index
    // buckets by real coordinates, not the mocked distance) and every pair is a candidate.

    private const double FarBeyondClosureMeters = GameConstants.LoopClosureDistanceMeters * 100;
    private const double HairBeyondClosureMeters = GameConstants.LoopClosureDistanceMeters + 0.0001;

    private static double[][] DistinctPointsInOneBucket(int length)
    {
        const double lngStepDegrees = 0.0000001;
        var path = new double[length][];
        for (var i = 0; i < length; i++)
            path[i] = [0.0, i * lngStepDegrees];
        return path;
    }

    private static HexGridService ServiceWhereOnlyScanPairReturns(double[][] path, double scanPairMeters)
    {
        var closingPoint = path[GameConstants.MinLoopPoints];
        var geo = new Mock<IGeoService>();
        geo.Setup(g => g.HaversineMeters(
                It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>()))
            .Returns(FarBeyondClosureMeters);
        geo.Setup(g => g.HaversineMeters(closingPoint[0], closingPoint[1], path[0][0], path[0][1]))
            .Returns(scanPairMeters);
        return new HexGridService(geo.Object);
    }

    [Fact]
    public void Scan_pair_exactly_at_the_closure_threshold_counts_as_closed()
    {
        var path = DistinctPointsInOneBucket(GameConstants.MinLoopPoints + 2);
        var svc = ServiceWhereOnlyScanPairReturns(path, GameConstants.LoopClosureDistanceMeters);

        Assert.True(svc.HasClosedLoop(path));
    }

    [Fact]
    public void Scan_pair_a_hair_beyond_the_closure_threshold_does_not_close()
    {
        var path = DistinctPointsInOneBucket(GameConstants.MinLoopPoints + 2);
        var svc = ServiceWhereOnlyScanPairReturns(path, HairBeyondClosureMeters);

        Assert.False(svc.HasClosedLoop(path));
    }

    // Endpoint-fallback boundary. A MinLoopPoints-length path never reaches the scan's
    // comparison (every candidate j exceeds i - MinLoopPoints, which is negative), so these
    // two cases pin the "<=" in the IsLoopClosed fallback alone.

    private static double[][] IdenticalCoordinatePath(int length)
    {
        var path = new double[length][];
        for (var i = 0; i < length; i++)
            path[i] = [0.0, 0.0];
        return path;
    }

    private static HexGridService ServiceWhereEveryPairReturns(double meters)
    {
        var geo = new Mock<IGeoService>();
        geo.Setup(g => g.HaversineMeters(
                It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>()))
            .Returns(meters);
        return new HexGridService(geo.Object);
    }

    [Fact]
    public void Endpoints_exactly_at_the_closure_threshold_count_as_closed()
    {
        var svc = ServiceWhereEveryPairReturns(GameConstants.LoopClosureDistanceMeters);

        Assert.True(svc.HasClosedLoop(IdenticalCoordinatePath(GameConstants.MinLoopPoints)));
    }

    [Fact]
    public void Endpoints_a_hair_beyond_the_closure_threshold_do_not_close()
    {
        var svc = ServiceWhereEveryPairReturns(HairBeyondClosureMeters);

        Assert.False(svc.HasClosedLoop(IdenticalCoordinatePath(GameConstants.MinLoopPoints)));
    }

    // ── Interior closure vs. endpoint-only closure ────────────────────────────────
    // Proves HasClosedLoop scans for ANY qualifying pair, not just path[0] vs path[^1] — a
    // regression that reduced it to an endpoint-only check would still pass every other test
    // in this suite (start/end happen to coincide there) but silently miss loops that close
    // partway through a longer walk, which is exactly the real gameplay case.

    [Fact]
    public void A_loop_that_closes_partway_through_the_path_counts_even_when_the_endpoints_dont_match()
    {
        const int length = 25;
        var path = DistinctPointsInOneBucket(length);

        var geo = new Mock<IGeoService>();
        // Default: far apart (no closure) for any pair...
        geo.Setup(g => g.HaversineMeters(
                It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>()))
            .Returns(FarBeyondClosureMeters);
        // ...except point 20 back to point 0, which closes the loop well before the path ends.
        geo.Setup(g => g.HaversineMeters(path[20][0], path[20][1], path[0][0], path[0][1]))
            .Returns(1.0);

        var svc = new HexGridService(geo.Object);

        Assert.True(svc.HasClosedLoop(path));
    }

    [Fact]
    public void No_pair_within_threshold_and_endpoints_far_apart_does_not_close()
    {
        var svc = ServiceWhereEveryPairReturns(FarBeyondClosureMeters);

        Assert.False(svc.HasClosedLoop(IdenticalCoordinatePath(30)));
    }

    // ── Real-geometry sanity checks (no mocking) ─────────────────────────────

    [Fact]
    public void A_real_closed_square_walk_closes()
    {
        var svc = Service();
        double[][] path = TestGeometry.Square(sideMeters: 100, pointsPerSide: 8);

        Assert.True(svc.HasClosedLoop(path));
    }

    [Fact]
    public void A_straight_line_walk_that_never_returns_does_not_close()
    {
        var svc = Service();
        var path = new double[GameConstants.MinLoopPoints + 5][];
        for (var i = 0; i < path.Length; i++)
            path[i] = [i * 0.001, 0.0]; // marching north, ~111m per step, never doubling back

        Assert.False(svc.HasClosedLoop(path));
    }
}
