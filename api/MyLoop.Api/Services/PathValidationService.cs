using MyLoop.Api.Constants;

namespace MyLoop.Api.Services;

/// <summary>
/// Server-side anti-cheat: validates that walk paths are physically plausible.
/// Checks maximum speed, minimum duration, and path smoothness.
/// </summary>
public class PathValidationService : IPathValidationService
{
    private readonly ILogger<PathValidationService> _logger;

    public PathValidationService(ILogger<PathValidationService> logger)
    {
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
    /// Assumes points are roughly equidistant in time (~5 seconds apart from GPS sampling).
    /// </summary>
    private string? ValidateSpeed(double[][] path)
    {
        int violations = 0;
        for (int i = 1; i < path.Length; i++)
        {
            var distanceMeters = HaversineDistance(path[i - 1], path[i]);
            // GPS sampling interval is ~5 seconds. Max plausible speed = 30 km/h (8.33 m/s).
            // Over 5 seconds that's ~42m. Use generous threshold of 60m to account for GPS drift.
            if (distanceMeters > AntiCheatConstants.MaxDistanceBetweenPointsMeters)
            {
                violations++;
            }
        }

        // Allow up to 5% violations (GPS can occasionally jump)
        var violationRate = (double)violations / (path.Length - 1);
        if (violationRate > AntiCheatConstants.MaxSpeedViolationRate)
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
        // Minimum time = distance / max speed (30 km/h = 8.33 m/s)
        var minDurationSeconds = totalDistance / AntiCheatConstants.MaxSpeedMetersPerSecond;
        // Implied duration = number of points * sampling interval (5s)
        var impliedDurationSeconds = (path.Length - 1) * AntiCheatConstants.GpsSamplingIntervalSeconds;

        if (impliedDurationSeconds < minDurationSeconds * AntiCheatConstants.DurationToleranceFactor)
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

        // Real GPS paths have stdDev > 5° typically. Spoofed linear paths have < 2°.
        if (stdDev < AntiCheatConstants.MinBearingStdDev)
        {
            _logger.LogWarning("Path rejected: bearing stdDev {StdDev:F2}° — suspiciously smooth", stdDev);
            return "Path rejected — movement pattern is not consistent with walking";
        }

        return null;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────────

    private static double HaversineDistance(double[] p1, double[] p2)
    {
        const double R = 6371000; // Earth radius in meters
        var lat1 = p1[0] * Math.PI / 180;
        var lat2 = p2[0] * Math.PI / 180;
        var dLat = (p2[0] - p1[0]) * Math.PI / 180;
        var dLng = (p2[1] - p1[1]) * Math.PI / 180;

        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1) * Math.Cos(lat2) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return R * c;
    }

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
