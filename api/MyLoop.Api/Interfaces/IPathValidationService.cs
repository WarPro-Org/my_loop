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
}
