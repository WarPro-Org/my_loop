namespace MyLoop.Modules.Rules;

/// <summary>
/// Every tunable game-rule number, bound from the <c>GameRules</c> section of appsettings.json
/// (FR1, requirement #20). Tuning a number means editing that file and redeploying — no code
/// change. <see cref="Version"/> must be bumped on every change so each walk can record which
/// rules decided it and past results never change silently.
/// </summary>
/// <remarks>
/// A missing setting stops the server at startup (<see cref="GameRulesPresenceValidator"/>)
/// instead of silently running with a zero; <see cref="GameRulesValidator"/> rejects bad values.
/// </remarks>
public sealed class GameRules
{
    public const string SectionName = "GameRules";

    /// <summary>Rules version. Bump it on every change to any value below.</summary>
    public int Version { get; init; }

    public LoopRules Loop { get; init; } = new();
    public GpsRules Gps { get; init; } = new();
    public AntiCheatRules AntiCheat { get; init; } = new();
    public AutoEndRules AutoEnd { get; init; } = new();
}

/// <summary>When a path counts as a closed loop, and which loops are big enough to capture.</summary>
public sealed class LoopRules
{
    /// <summary>How close the path must come back to an earlier point to close a loop.</summary>
    public double ClosureDistanceMeters { get; init; }

    /// <summary>Fewest GPS points a loop must span, so jitter while standing still never closes one.</summary>
    public int MinPoints { get; init; }

    /// <summary>
    /// Index where the loop scan starts. It has no effect while it is at most <see cref="MinPoints"/>,
    /// because a loop already needs that many points (FR6 gives it a meaning or removes it).
    /// </summary>
    public int SkipNeighbors { get; init; }

    /// <summary>Loops smaller than this capture nothing.</summary>
    public double MinAreaSquareMeters { get; init; }
}

/// <summary>GPS quality.</summary>
public sealed class GpsRules
{
    /// <summary>Points with a reported accuracy worse than this are ignored.</summary>
    public double AccuracyThresholdMeters { get; init; }
}

/// <summary>Speed and plausibility checks. Server-only: never sent to the app (#15).</summary>
public sealed class AntiCheatRules
{
    /// <summary>Fastest per-hop speed that still counts as walking or running.</summary>
    public double MaxSpeedMetersPerSecond { get; init; }

    /// <summary>
    /// Fastest sustained average speed over a batch. Intentionally a little above
    /// <see cref="MaxSpeedMetersPerSecond"/>: averaging cancels GPS noise, so this still catches
    /// vehicles without rejecting fast runners.
    /// </summary>
    public double MaxAverageSpeedMetersPerSecond { get; init; }

    /// <summary>Extra distance allowed per hop for GPS drift — even a still phone wanders ~30 m between fixes.</summary>
    public double GpsDriftMarginMeters { get; init; }

    /// <summary>Largest plausible jump between consecutive points (includes a GPS drift margin).</summary>
    public double MaxDistanceBetweenPointsMeters { get; init; }

    /// <summary>Share of hops (0–1) allowed to break the speed limit before rejecting, for GPS jumps.</summary>
    public double MaxSpeedViolationRate { get; init; }

    /// <summary>Expected seconds between GPS points, used when timestamps are missing.</summary>
    public double GpsSamplingIntervalSeconds { get; init; }

    /// <summary>A path must span at least this fraction (0–1) of the minimum plausible duration.</summary>
    public double DurationToleranceFactor { get; init; }

    /// <summary>Minimum bearing spread (degrees); spoofed straight-line paths fall below it.</summary>
    public double MinBearingStdDev { get; init; }
}

/// <summary>
/// When the phone ends a forgotten walk on its own (FR2, #34). Sent to the app; its own group, never inside
/// <see cref="AntiCheatRules"/>, because these numbers are walk rules, not cheat checks.
/// </summary>
public sealed class AutoEndRules
{
    /// <summary>Average speed over <see cref="VehicleSeconds"/> above which the walk counts as a vehicle ride.</summary>
    public double VehicleSpeedMetersPerSecond { get; init; }

    /// <summary>How long the phone must move faster than <see cref="VehicleSpeedMetersPerSecond"/> to end the walk.</summary>
    public int VehicleSeconds { get; init; }

    /// <summary>Every fix within this distance of the fixes' average counts as standing still.</summary>
    public double StillRadiusMeters { get; init; }

    /// <summary>
    /// Recorded path below this length over <see cref="StillSeconds"/> still counts as still, so GPS jitter doesn't
    /// reset the count while slow laps inside the radius don't count as still.
    /// </summary>
    public double StillMaxWalkedMeters { get; init; }

    /// <summary>How long the phone must stay still to end the walk.</summary>
    public int StillSeconds { get; init; }
}
