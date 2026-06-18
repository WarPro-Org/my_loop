namespace MyLoop.Api.Constants;

/// <summary>
/// Anti-cheat thresholds for path validation.
/// </summary>
public static class AntiCheatConstants
{
    /// <summary>Max speed in m/s (30 km/h — fast jogging).</summary>
    public const double MaxSpeedMetersPerSecond = 8.33;

    /// <summary>
    /// Max sustained <b>average</b> speed (m/s) across a batch window (~32 km/h).
    /// The per-hop drift margin lets steady vehicle travel (~50 km/h) slip past the
    /// per-hop gate (issue #37); averaging hop distances over the whole window cancels
    /// GPS noise, and no human gait (walk/run/sprint/cycle) sustains this — so it
    /// catches cars/metros without false-positiving real walkers.
    /// <para>
    /// NOTE: this is intentionally <b>higher</b> than the nominal per-hop
    /// <see cref="MaxSpeedMetersPerSecond"/> (8.33) — not a bug. The per-hop gate's
    /// <i>effective</i> ceiling is ~12 m/s (<see cref="MaxDistanceBetweenPointsMeters"/> = 60 m
    /// over a ~5 s hop), so 9.0 m/s is in fact stricter than the per-hop gate in practice while
    /// still clearing the fastest human gait over a noisy window. Do NOT "fix" the apparent
    /// inversion by lowering this toward 8.33 — that reintroduces false positives for fast runners.
    /// </para>
    /// </summary>
    public const double MaxAverageSpeedMetersPerSecond = 9.0;

    /// <summary>GPS sampling interval in seconds (client sends a point every ~5s).</summary>
    public const double GpsSamplingIntervalSeconds = 5.0;

    /// <summary>
    /// Max plausible distance between consecutive GPS points (meters).
    /// = MaxSpeed * SamplingInterval * 1.5 safety margin for GPS drift.
    /// </summary>
    public const double MaxDistanceBetweenPointsMeters = 60.0;

    /// <summary>
    /// Fraction of point pairs that can exceed speed limit before rejection.
    /// GPS occasionally jumps — allow up to 5%.
    /// </summary>
    public const double MaxSpeedViolationRate = 0.05;

    /// <summary>
    /// If implied duration is less than this fraction of minimum required duration, reject.
    /// 0.5 = path must have at least half the expected number of points.
    /// </summary>
    public const double DurationToleranceFactor = 0.5;

    /// <summary>
    /// Minimum bearing standard deviation (degrees).
    /// Real GPS paths have natural jitter (&gt;5°). Spoofed linear paths have &lt;2°.
    /// </summary>
    public const double MinBearingStdDev = 2.0;
}
