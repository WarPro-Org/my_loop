namespace MyLoop.Api.Interfaces;

/// <summary>
/// Validates walk paths for physical plausibility.
/// Rejects GPS spoofing, teleportation, and impossibly fast movement.
/// </summary>
public interface IPathValidationService
{
    /// <summary>
    /// Validates a path and returns an error message if suspicious, or null if valid.
    /// </summary>
    string? Validate(double[][] path);

    /// <summary>
    /// Validates a sequence of timestamped GPS points (real-time batch-step claiming)
    /// for physically plausible movement between consecutive samples. Returns an error
    /// message when too many hops imply impossible speed (teleport / GPS spoofing),
    /// or null if the batch is acceptable.
    /// </summary>
    string? ValidateConsecutivePoints(IReadOnlyList<(double Lat, double Lng, DateTime CapturedAt)> points);

    /// <summary>
    /// Smoothness (bearing-stddev) gate for a real-time batch-step window (issue #52).
    /// Real GPS tracks jitter; a synthetic dead-straight or perfectly regular path has an
    /// unnaturally low bearing-change standard deviation. Returns an error message when the
    /// window is suspiciously smooth, or null when it has enough natural jitter — or when the
    /// window is too short to judge (fewer than the minimum points). Mirrors the smoothness
    /// check the loop-claim path already applies via <see cref="Validate"/>, which the
    /// batch-step path (the live claim path) previously skipped.
    /// </summary>
    string? ValidateSmoothness(IReadOnlyList<(double Lat, double Lng)> points);
}
