using MyLoop.Modules.Rules;

namespace MyLoop.Api.Tests;

/// <summary>
/// Game rules for the pre-0.1 tests, matching the values in appsettings.json when FR1 moved
/// the loop and anti-cheat numbers out of the constants files.
/// </summary>
internal static class TestRules
{
    public static readonly GameRules Rules = new()
    {
        Version = 1,
        Loop = new LoopRules { ClosureDistanceMeters = 50, MinPoints = 20, SkipNeighbors = 10, MinAreaSquareMeters = 5000 },
        Gps = new GpsRules { AccuracyThresholdMeters = 50 },
        Gap = new GapRules { MaxSeconds = 60, MaxMeters = 100 },
        AntiCheat = new AntiCheatRules
        {
            MaxSpeedMetersPerSecond = 8.33,
            MaxAverageSpeedMetersPerSecond = 9.0,
            GpsDriftMarginMeters = 30,
            MaxDistanceBetweenPointsMeters = 60,
            MaxSpeedViolationRate = 0.05,
            GpsSamplingIntervalSeconds = 5,
            DurationToleranceFactor = 0.5,
            MinBearingStdDev = 2.0,
        },
        AutoEnd = new AutoEndRules { IdleMinutes = 30, VehicleSpeedKmh = 35, VehicleMinutes = 3 },
        SafetyAlarm = new SafetyAlarmRules { DelaySeconds = 120 },
        Guests = new GuestRules { InactivityDays = 30 },
    };

    public static readonly IRuleSettings Settings = new RuleSettings(Microsoft.Extensions.Options.Options.Create(Rules));

    public static LoopRules Loop => Rules.Loop;
}
