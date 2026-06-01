namespace MyLoop.Api.Interfaces;

/// <summary>
/// Input validation — display names, colors, avatar IDs.
/// </summary>
public interface IValidationService
{
    /// <summary>
    /// Validates a display name. Returns null if valid, error string if invalid.
    /// </summary>
    string? ValidateDisplayName(string? name);

    /// <summary>
    /// Validates a hex color string. Returns null if valid, error string if invalid.
    /// </summary>
    string? ValidateColor(string? color);

    /// <summary>
    /// Validates an avatar ID. Returns null if valid, error string if invalid.
    /// </summary>
    string? ValidateAvatarId(int avatarId);
}
