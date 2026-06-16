using Microsoft.Extensions.Logging.Abstractions;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Pure-logic tests (no database) for the batch-step anti-cheat speed gate added to
/// close CRITICAL-7 / HIGH-13: batch-step claiming previously bypassed all path
/// validation, so a spoofer could teleport across the map and claim hexes.
/// </summary>
public class PathValidationServiceTests
{
    private static PathValidationService Service() =>
        new(NullLogger<PathValidationService>.Instance);

    private static (double, double, DateTime) P(double lat, double lng, DateTime t) => (lat, lng, t);

    [Fact]
    public void Plausible_walking_batch_is_accepted()
    {
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        // ~11m north every 5s ≈ 2.2 m/s — a brisk walk.
        var points = new List<(double, double, DateTime)>
        {
            P(12.9000, 77.5000, t0),
            P(12.9001, 77.5000, t0.AddSeconds(5)),
            P(12.9002, 77.5000, t0.AddSeconds(10)),
            P(12.9003, 77.5000, t0.AddSeconds(15)),
        };

        Assert.Null(Service().ValidateConsecutivePoints(points));
    }

    [Fact]
    public void Teleport_between_consecutive_points_is_rejected()
    {
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        // Bangalore → New York in 5 seconds.
        var points = new List<(double, double, DateTime)>
        {
            P(12.9000, 77.5000, t0),
            P(40.7128, -74.0060, t0.AddSeconds(5)),
        };

        Assert.NotNull(Service().ValidateConsecutivePoints(points));
    }

    [Fact]
    public void Single_point_or_empty_batch_is_accepted()
    {
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        Assert.Null(Service().ValidateConsecutivePoints(new List<(double, double, DateTime)>()));
        Assert.Null(Service().ValidateConsecutivePoints(new List<(double, double, DateTime)> { P(12.9, 77.5, t0) }));
    }

    [Fact]
    public void Missing_timestamps_fall_back_to_sampling_cadence_and_tolerate_small_hops()
    {
        // All timestamps identical (elapsed = 0) → service assumes nominal cadence
        // instead of dividing by zero; small ~11m hops must still pass.
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        var points = new List<(double, double, DateTime)>
        {
            P(12.9000, 77.5000, t0),
            P(12.9001, 77.5000, t0),
            P(12.9002, 77.5000, t0),
        };

        Assert.Null(Service().ValidateConsecutivePoints(points));
    }

    [Fact]
    public void Sustained_vehicle_speed_batch_is_rejected()
    {
        // Regression for issue #37: a car/metro travelling ~40 km/h produces ~55.6m hops
        // every 5s (≈11.1 m/s). Each hop is below the per-hop ceiling
        // (8.33*5 + 30 = 71.65m), so the per-hop gate alone accepts it — exactly the bug.
        // The window-average gate (avg ≈ 11.1 m/s > 9.0) must reject it.
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        var points = new List<(double, double, DateTime)> { P(12.9000, 77.5000, t0) };
        for (var i = 1; i <= 12; i++)
            points.Add(P(12.9000 + i * 0.0005, 77.5000, t0.AddSeconds(i * 5))); // ~55.6m/hop

        Assert.NotNull(Service().ValidateConsecutivePoints(points));
    }

    [Fact]
    public void Fast_run_average_is_accepted()
    {
        // Guards against false positives: a fast run (~5 m/s, ~25m hops every 5s) is well
        // under the sustained-speed gate and must still be accepted.
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        var points = new List<(double, double, DateTime)> { P(12.9000, 77.5000, t0) };
        for (var i = 1; i <= 12; i++)
            points.Add(P(12.9000 + i * 0.000225, 77.5000, t0.AddSeconds(i * 5))); // ~25m/hop ≈ 5 m/s

        Assert.Null(Service().ValidateConsecutivePoints(points));
    }

    [Fact]
    public void Occasional_gps_jump_within_tolerance_is_accepted()
    {
        var t0 = new DateTime(2026, 6, 11, 9, 0, 0, DateTimeKind.Utc);
        // 20 normal hops + a single ~150m GPS spike = 1/20 = 5% ≤ tolerance.
        var points = new List<(double, double, DateTime)> { P(12.9000, 77.5000, t0) };
        for (var i = 1; i <= 20; i++)
            points.Add(P(12.9000 + i * 0.0001, 77.5000, t0.AddSeconds(i * 5)));
        // Inject one spike well beyond plausible distance.
        points.Add(P(12.9000 + 21 * 0.0001 + 0.0015, 77.5000, t0.AddSeconds(21 * 5)));

        Assert.Null(Service().ValidateConsecutivePoints(points));
    }
}
