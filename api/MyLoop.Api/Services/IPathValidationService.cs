namespace MyLoop.Api.Services;

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
}
