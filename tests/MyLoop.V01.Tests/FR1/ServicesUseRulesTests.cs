using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using MyLoop.Api.Services;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>
/// FR1: the server's loop and anti-cheat code take their numbers from the rules, so changing a
/// setting changes the result. The old tests can't show this: they run with unchanged values.
/// </summary>
public class ServicesUseRulesTests
{
    private const double CircleRadiusMeters = 150;
    private const int CircleSteps = 25;                   // the last point lands ~38 m from the first
    private const double HopMeters = 44;                  // one hop every sampling interval
    private const double SamplingIntervalSeconds = 5;
    private const double MetersPerDegreeLat = 111_320;
    private const double ZigzagStepMeters = 35;          // north per point
    // Metres east (+) or west (-) of the centre line, repeated. Uneven on purpose: the smoothness
    // check measures how much the turns vary, so an even zigzag would look like a straight line.
    private static readonly double[] ZigzagSwayMeters = [0, 8, -4, 10, -8, 3, -10, 6];
    private const int ZigzagPoints = 21;
    private const double TailHops = 10;                  // walked east after the circle closes

    // Messages of the three checks in PathValidationService.Validate.
    private const string SpeedCheck = "movement speed exceeds physical limits";
    private const string DurationCheck = "walk duration too short";
    private const string SmoothnessCheck = "not consistent with walking";

    private static IRuleSettings Rules(
        double closureDistanceMeters = 50, int minPoints = 20, int skipNeighbors = 10,
        double minAreaSquareMeters = 5000, double maxSpeedMetersPerSecond = 8.33,
        double maxAverageSpeedMetersPerSecond = 9.0, double gpsDriftMarginMeters = 30,
        double maxDistanceBetweenPointsMeters = 60, double maxSpeedViolationRate = 0.05,
        double gpsSamplingIntervalSeconds = SamplingIntervalSeconds, double durationToleranceFactor = 0.5,
        double minBearingStdDev = 2.0) =>
        new RuleSettings(Options.Create(new GameRules
        {
            Version = 1,
            Loop = new LoopRules
            {
                ClosureDistanceMeters = closureDistanceMeters,
                MinPoints = minPoints,
                SkipNeighbors = skipNeighbors,
                MinAreaSquareMeters = minAreaSquareMeters,
            },
            Gps = new GpsRules { AccuracyThresholdMeters = 50 },
            AntiCheat = new AntiCheatRules
            {
                MaxSpeedMetersPerSecond = maxSpeedMetersPerSecond,
                MaxAverageSpeedMetersPerSecond = maxAverageSpeedMetersPerSecond,
                GpsDriftMarginMeters = gpsDriftMarginMeters,
                MaxDistanceBetweenPointsMeters = maxDistanceBetweenPointsMeters,
                MaxSpeedViolationRate = maxSpeedViolationRate,
                GpsSamplingIntervalSeconds = gpsSamplingIntervalSeconds,
                DurationToleranceFactor = durationToleranceFactor,
                MinBearingStdDev = minBearingStdDev,
            },
        }));

    private static HexGridService Grid(IRuleSettings rules) => new(new GeoService(), rules);

    private static PathValidationService Validator(IRuleSettings rules) =>
        new(rules, NullLogger<PathValidationService>.Instance);

    /// <summary>A walk round a circle that stops one step short of where it started.</summary>
    private static double[][] AlmostClosedCircle()
    {
        const double centreLat = 51.5;
        const double centreLng = -0.12;
        var lngScale = Math.Cos(centreLat * Math.PI / 180);
        return Enumerable.Range(0, CircleSteps)
            .Select(k => 2 * Math.PI * k / CircleSteps)
            .Select(angle => new[]
            {
                centreLat + CircleRadiusMeters * Math.Sin(angle) / MetersPerDegreeLat,
                centreLng + CircleRadiusMeters * Math.Cos(angle) / (MetersPerDegreeLat * lngScale),
            })
            .ToArray();
    }

    /// <summary>
    /// The circle, then a straight walk away east, so the path's end is far from its start. The
    /// loop closes only in the middle of the path, where the scan after SkipNeighbors finds it.
    /// </summary>
    private static double[][] CircleThenWalkAway()
    {
        var circle = AlmostClosedCircle();
        var last = circle[^1];
        var lngScale = Math.Cos(last[0] * Math.PI / 180);
        var tail = Enumerable.Range(1, (int)TailHops)
            .Select(i => new[] { last[0], last[1] + i * HopMeters / (MetersPerDegreeLat * lngScale) });
        return [.. circle, .. tail];
    }

    /// <summary>
    /// A walk north that sways east and west: 35–41 m hops, one per sampling interval, and turns
    /// that vary like real GPS. It passes every check in <see cref="PathValidationService.Validate"/>
    /// with the shipped values.
    /// </summary>
    private static double[][] Zigzag()
    {
        const double startLat = 51.5;
        const double startLng = -0.12;
        var lngScale = Math.Cos(startLat * Math.PI / 180);
        return Enumerable.Range(0, ZigzagPoints)
            .Select(i => new[]
            {
                startLat + i * ZigzagStepMeters / MetersPerDegreeLat,
                startLng + ZigzagSwayMeters[i % ZigzagSwayMeters.Length] / (MetersPerDegreeLat * lngScale),
            })
            .ToArray();
    }

    private static List<(double Lat, double Lng, DateTime CapturedAt)> StraightHops(int count)
    {
        var start = new DateTime(2026, 1, 1, 8, 0, 0, DateTimeKind.Utc);
        return Enumerable.Range(0, count)
            .Select(i => (51.5 + i * HopMeters / MetersPerDegreeLat, -0.12,
                start.AddSeconds(i * SamplingIntervalSeconds)))
            .ToList();
    }

    [Fact]
    public void Loop_closure_distance_comes_from_the_rules()
    {
        var path = AlmostClosedCircle();

        Assert.True(new HexGridService(new GeoService(), Rules(closureDistanceMeters: 50)).HasClosedLoop(path));
        Assert.False(new HexGridService(new GeoService(), Rules(closureDistanceMeters: 30)).HasClosedLoop(path));
    }

    [Fact]
    public void Claimed_loops_use_the_closure_distance_from_the_rules()
    {
        var path = AlmostClosedCircle();

        Assert.Equal(1, new HexGridService(new GeoService(), Rules(closureDistanceMeters: 50)).ComputeCapturedTerritory(path).LoopCount);
        Assert.Equal(0, new HexGridService(new GeoService(), Rules(closureDistanceMeters: 30)).ComputeCapturedTerritory(path).LoopCount);
    }

    [Fact]
    public void Claimed_loops_use_the_minimum_area_from_the_rules()
    {
        var path = AlmostClosedCircle();   // encloses about 70,000 m²

        Assert.Equal(1, new HexGridService(new GeoService(), Rules(minAreaSquareMeters: 5_000)).ComputeCapturedTerritory(path).LoopCount);
        Assert.Equal(0, new HexGridService(new GeoService(), Rules(minAreaSquareMeters: 100_000)).ComputeCapturedTerritory(path).LoopCount);
    }

    [Fact]
    public void Gps_drift_margin_comes_from_the_rules()
    {
        var hops = StraightHops(count: 10);
        var lenient = new PathValidationService(Rules(gpsDriftMarginMeters: 30), NullLogger<PathValidationService>.Instance);
        var strict = new PathValidationService(Rules(gpsDriftMarginMeters: 0), NullLogger<PathValidationService>.Instance);

        Assert.Null(lenient.ValidateConsecutivePoints(hops));
        Assert.NotNull(strict.ValidateConsecutivePoints(hops));
    }

    [Fact]
    public void Loop_minimum_points_come_from_the_rules()
    {
        var path = AlmostClosedCircle();   // 25 points

        Assert.True(Grid(Rules(minPoints: 20)).HasClosedLoop(path));
        Assert.False(Grid(Rules(minPoints: 30)).HasClosedLoop(path));
    }

    [Fact]
    public void Loop_skip_neighbors_comes_from_the_rules()
    {
        var path = CircleThenWalkAway();   // 35 points; the loop closes at point 24

        Assert.True(Grid(Rules(skipNeighbors: 10)).HasClosedLoop(path));
        Assert.False(Grid(Rules(skipNeighbors: 40)).HasClosedLoop(path));
    }

    [Fact]
    public void Shipped_values_accept_the_zigzag_walk()
    {
        // Positive control for the tests below: each one changes a single setting.
        Assert.Null(Validator(Rules()).Validate(Zigzag()));
    }

    [Fact]
    public void Max_distance_between_points_comes_from_the_rules()
    {
        Assert.Null(Validator(Rules(maxDistanceBetweenPointsMeters: 60)).Validate(Zigzag()));
        Assert.Contains(SpeedCheck, Validator(Rules(maxDistanceBetweenPointsMeters: 30)).Validate(Zigzag()));
    }

    [Fact]
    public void Max_speed_violation_rate_comes_from_the_rules()
    {
        // Every hop (35 m or more) breaks a 30 m limit; the rate decides whether that's tolerated.
        Assert.Null(Validator(Rules(maxDistanceBetweenPointsMeters: 30, maxSpeedViolationRate: 1)).Validate(Zigzag()));
        Assert.Contains(SpeedCheck, Validator(Rules(maxDistanceBetweenPointsMeters: 30, maxSpeedViolationRate: 0.05)).Validate(Zigzag()));
    }

    [Fact]
    public void Gps_sampling_interval_comes_from_the_rules()
    {
        // 35–41 m per point at 8.33 m/s needs 4.2–4.9 s; half of that is allowed.
        Assert.Null(Validator(Rules(gpsSamplingIntervalSeconds: 5)).Validate(Zigzag()));
        Assert.Contains(DurationCheck, Validator(Rules(gpsSamplingIntervalSeconds: 1)).Validate(Zigzag()));
    }

    [Fact]
    public void Duration_tolerance_comes_from_the_rules()
    {
        // 3 s per point: enough for half the minimum (4.2–4.9 s), not for all of it.
        Assert.Null(Validator(Rules(gpsSamplingIntervalSeconds: 3, durationToleranceFactor: 0.5)).Validate(Zigzag()));
        Assert.Contains(DurationCheck, Validator(Rules(gpsSamplingIntervalSeconds: 3, durationToleranceFactor: 1)).Validate(Zigzag()));
    }

    [Fact]
    public void Min_bearing_std_dev_comes_from_the_rules()
    {
        Assert.Null(Validator(Rules(minBearingStdDev: 2)).Validate(Zigzag()));
        Assert.Contains(SmoothnessCheck, Validator(Rules(minBearingStdDev: 1000)).Validate(Zigzag()));
    }

    [Fact]
    public void Max_speed_comes_from_the_rules()
    {
        var hops = StraightHops(count: 10);   // 44 m every 5 s: 8.8 m/s

        Assert.Null(Validator(Rules(maxSpeedMetersPerSecond: 8.33)).ValidateConsecutivePoints(hops));
        Assert.NotNull(Validator(Rules(maxSpeedMetersPerSecond: 2)).ValidateConsecutivePoints(hops));
    }

    [Fact]
    public void Max_average_speed_comes_from_the_rules()
    {
        var hops = StraightHops(count: 10);   // 8.8 m/s on average; every hop is within the per-hop limit

        Assert.Null(Validator(Rules(maxAverageSpeedMetersPerSecond: 9)).ValidateConsecutivePoints(hops));
        Assert.NotNull(Validator(Rules(maxAverageSpeedMetersPerSecond: 8)).ValidateConsecutivePoints(hops));
    }
}
