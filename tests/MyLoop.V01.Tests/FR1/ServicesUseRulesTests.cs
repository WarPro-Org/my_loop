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

    private static IRuleSettings Rules(
        double closureDistanceMeters = 50, double gpsDriftMarginMeters = 30, double minAreaSquareMeters = 5000) =>
        new RuleSettings(Options.Create(new GameRules
        {
            Version = 1,
            Loop = new LoopRules
            {
                ClosureDistanceMeters = closureDistanceMeters,
                MinPoints = 20,
                SkipNeighbors = 10,
                MinAreaSquareMeters = minAreaSquareMeters,
            },
            Gps = new GpsRules { AccuracyThresholdMeters = 50 },
            AntiCheat = new AntiCheatRules
            {
                MaxSpeedMetersPerSecond = 8.33,
                MaxAverageSpeedMetersPerSecond = 9.0,
                GpsDriftMarginMeters = gpsDriftMarginMeters,
                MaxDistanceBetweenPointsMeters = 60,
                MaxSpeedViolationRate = 0.05,
                GpsSamplingIntervalSeconds = SamplingIntervalSeconds,
                DurationToleranceFactor = 0.5,
                MinBearingStdDev = 2.0,
            },
        }));

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
}
