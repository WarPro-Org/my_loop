using MyLoop.Api.Constants;
using MyLoop.Modules.Rules;

namespace MyLoop.Api.Services;

/// <summary>
/// Server-side anti-cheat: validates that walk paths are physically plausible.
/// Checks maximum speed, minimum duration, and path smoothness.
/// </summary>
public class PathValidationService : IPathValidationService
{
    private readonly AntiCheatRules _antiCheat;
    private readonly ILogger<PathValidationService> _logger;

    public PathValidationService(IRuleSettings rules, ILogger<PathValidationService> logger)
    {
        _antiCheat = rules.Current.AntiCheat;
        _logger = logger;
    }

    public string? Validate(double[][] path)
    {
        if (path.Length < 2) return "Path too short";

        var speedError = ValidateSpeed(path);
        if (speedError != null) return speedError;

        var durationError = ValidateDuration(path);
        if (durationError != null) return durationError;

        var smoothnessError = ValidateSmoothness(path);
        if (smoothnessError != null) return smoothnessError;

        return null;
    }

    /// <summary>
    /// Rejects paths where any two consecutive points imply movement faster than max walking/running speed.
    /// Assumes points are roughly equidistant in time (one GPS sample per sampling interval).
    /// </summary>
    private string? ValidateSpeed(double[][] path)
    {
        int violations = 0;
        for (int i = 1; i < path.Length; i++)
        {
            var distanceMeters = HaversineDistance(path[i - 1], path[i]);
            // MaxDistanceBetweenPointsMeters is its own setting (GameRules:AntiCheat), sized to cover one
            // sampling interval at max speed plus GPS drift; changing those two doesn't move it.
            if (distanceMeters > _antiCheat.MaxDistanceBetweenPointsMeters)
            {
                violations++;
            }
        }

        // GPS occasionally jumps, so a small share of violating hops is tolerated.
        var violationRate = (double)violations / (path.Length - 1);
        if (violationRate > _antiCheat.MaxSpeedViolationRate)
        {
            _logger.LogWarning(
                "Path rejected: {Rate:P1} speed violations ({Count}/{Total})",
                violationRate, violations, path.Length - 1);
            return "Path rejected — movement speed exceeds physical limits";
        }

        return null;
    }

    /// <summary>
    /// Rejects paths where the total distance is too high for the implied duration.
    /// Path length * GPS interval gives approximate duration.
    /// </summary>
    private string? ValidateDuration(double[][] path)
    {
        var totalDistance = CalculateTotalDistance(path);
        // Minimum time = distance / max speed.
        var minDurationSeconds = totalDistance / _antiCheat.MaxSpeedMetersPerSecond;
        // Implied duration = number of points × sampling interval.
        var impliedDurationSeconds = (path.Length - 1) * _antiCheat.GpsSamplingIntervalSeconds;

        if (impliedDurationSeconds < minDurationSeconds * _antiCheat.DurationToleranceFactor)
        {
            _logger.LogWarning(
                "Path rejected: distance {Dist:F0}m implies min {Min:F0}s but path only has {Implied:F0}s of points",
                totalDistance, minDurationSeconds, impliedDurationSeconds);
            return "Path rejected — walk duration too short for distance covered";
        }

        return null;
    }

    /// <summary>
    /// Detects suspiciously smooth paths. Real GPS data has jitter (noise).
    /// Spoofed paths tend to have unnaturally consistent bearing changes.
    /// Measures standard deviation of bearing changes — too low = suspicious.
    /// </summary>
    private string? ValidateSmoothness(double[][] path)
    {
        if (path.Length < 10) return null; // Not enough points to analyze

        var bearingChanges = new List<double>();
        for (int i = 2; i < path.Length; i++)
        {
            var bearing1 = CalculateBearing(path[i - 2], path[i - 1]);
            var bearing2 = CalculateBearing(path[i - 1], path[i]);
            var change = NormalizeBearingChange(bearing2 - bearing1);
            bearingChanges.Add(change);
        }

        if (bearingChanges.Count < 5) return null;

        var mean = bearingChanges.Average();
        var variance = bearingChanges.Average(c => (c - mean) * (c - mean));
        var stdDev = Math.Sqrt(variance);

        // Real GPS paths jitter (typically > 5°); spoofed straight-line paths barely vary.
        if (stdDev < _antiCheat.MinBearingStdDev)
        {
            _logger.LogWarning("Path rejected: bearing stdDev {StdDev:F2}° — suspiciously smooth", stdDev);
            return "Path rejected — movement pattern is not consistent with walking";
        }

        return null;
    }

    /// <summary>
    /// Speed gate for real-time batch-step points. Unlike <see cref="Validate"/>, these
    /// points carry real capture timestamps, so we bound each hop by the time actually
    /// elapsed (plus a GPS-uncertainty margin) instead of assuming a fixed sampling cadence.
    /// A hop is implausible only if the straight-line distance exceeds what max walking
    /// speed could cover in the elapsed time — this rejects teleport/spoof jumps between
    /// rapid samples while tolerating legitimately long gaps in the write-ahead-log drain.
    /// </summary>
    public string? ValidateConsecutivePoints(IReadOnlyList<(double Lat, double Lng, DateTime CapturedAt)> points)
    {
        if (points.Count < 2) return null;

        var gpsDriftMarginMeters = _antiCheat.GpsDriftMarginMeters;

        var violations = 0;
        var totalDistanceMeters = 0.0;
        for (var i = 1; i < points.Count; i++)
        {
            var prev = points[i - 1];
            var curr = points[i];

            var distanceMeters = HaversineDistance(
                [prev.Lat, prev.Lng], [curr.Lat, curr.Lng]);
            totalDistanceMeters += distanceMeters;

            var elapsedSeconds = (curr.CapturedAt - prev.CapturedAt).TotalSeconds;
            // Missing/disordered timestamps → fall back to the nominal sampling cadence
            // rather than dividing by zero or trusting a negative interval.
            if (elapsedSeconds <= 0)
                elapsedSeconds = _antiCheat.GpsSamplingIntervalSeconds;

            var maxPlausibleMeters =
                _antiCheat.MaxSpeedMetersPerSecond * elapsedSeconds + gpsDriftMarginMeters;

            if (distanceMeters > maxPlausibleMeters)
                violations++;
        }

        var violationRate = (double)violations / (points.Count - 1);
        if (violationRate > _antiCheat.MaxSpeedViolationRate)
        {
            _logger.LogWarning(
                "Batch rejected: {Rate:P1} implausible-speed hops ({Count}/{Total})",
                violationRate, violations, points.Count - 1);
            return "Movement speed exceeds physical limits";
        }

        // Sustained-speed gate (issue #37): the per-hop drift margin alone lets steady
        // vehicle travel (~50 km/h) through, because each hop stays under the inflated
        // per-hop ceiling. Averaging hop distances over the whole window cancels GPS
        // noise, so a sustained average above human gait reliably flags cars/metros.
        // Skip when total elapsed ≤ 0 (missing/disordered timestamps) — same fallback
        // rationale as the per-hop loop above.
        var totalElapsedSeconds = (points[^1].CapturedAt - points[0].CapturedAt).TotalSeconds;
        if (totalElapsedSeconds > 0)
        {
            var averageSpeed = totalDistanceMeters / totalElapsedSeconds;
            if (averageSpeed > _antiCheat.MaxAverageSpeedMetersPerSecond)
            {
                _logger.LogWarning(
                    "Batch rejected: sustained average speed {Speed:F1} m/s over {Seconds:F0}s exceeds limit",
                    averageSpeed, totalElapsedSeconds);
                return "Movement speed exceeds physical limits";
            }
        }

        return null;
    }

    /// <summary>
    /// Public smoothness gate for real-time batch-step windows (issue #52). Adapts the
    /// timestamp-free lat/lng list to the same bearing-stddev logic the loop-claim path
    /// uses, so a synthetic dead-straight batch is rejected on the live claim path too.
    /// Windows shorter than the analysis minimum are accepted (returns null), matching the
    /// loop-claim behaviour — cross-batch smoothness is out of scope for this fix.
    /// </summary>
    public string? ValidateSmoothness(IReadOnlyList<(double Lat, double Lng)> points)
    {
        var path = new double[points.Count][];
        for (var i = 0; i < points.Count; i++)
            path[i] = [points[i].Lat, points[i].Lng];
        return ValidateSmoothness(path);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Great-circle distance between two <c>[lat, lng]</c> pairs, delegating to the API's single
    /// implementation. This method used to carry a second copy of the Haversine formula with the
    /// earth radius hardcoded (#139 D3); the shared one uses
    /// <see cref="GameConstants.EarthRadiusMeters"/>, which is the same value, so distances are
    /// unchanged.
    /// </summary>
    private static double HaversineDistance(double[] p1, double[] p2) =>
        GeoService.Haversine(p1[0], p1[1], p2[0], p2[1]);

    private static double CalculateTotalDistance(double[][] path)
    {
        double total = 0;
        for (int i = 1; i < path.Length; i++)
        {
            total += HaversineDistance(path[i - 1], path[i]);
        }
        return total;
    }

    private static double CalculateBearing(double[] from, double[] to)
    {
        var lat1 = from[0] * Math.PI / 180;
        var lat2 = to[0] * Math.PI / 180;
        var dLng = (to[1] - from[1]) * Math.PI / 180;

        var x = Math.Sin(dLng) * Math.Cos(lat2);
        var y = Math.Cos(lat1) * Math.Sin(lat2) - Math.Sin(lat1) * Math.Cos(lat2) * Math.Cos(dLng);
        var bearing = Math.Atan2(x, y) * 180 / Math.PI;
        return (bearing + 360) % 360;
    }

    private static double NormalizeBearingChange(double change)
    {
        while (change > 180) change -= 360;
        while (change < -180) change += 360;
        return Math.Abs(change);
    }
}
