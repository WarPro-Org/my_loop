using System.Text.RegularExpressions;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Services;

/// <summary>
/// Centralized input validation for the API.
/// </summary>
public partial class ValidationService : IValidationService
{
    private static readonly Regex DisplayNameRegex = MyDisplayNameRegex();
    private static readonly Regex HexColorRegex = MyHexColorRegex();

    public string? ValidateDisplayName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return "DisplayName is required";

        var trimmed = name.Trim();

        if (trimmed.Length < GameConstants.MinDisplayNameLength)
            return $"DisplayName must be at least {GameConstants.MinDisplayNameLength} characters";

        if (trimmed.Length > GameConstants.MaxDisplayNameLength)
            return $"DisplayName must be {GameConstants.MaxDisplayNameLength} characters or less";

        if (!DisplayNameRegex.IsMatch(trimmed))
            return "DisplayName contains invalid characters (letters, numbers, spaces, hyphens only)";

        return null;
    }

    public string? ValidateColor(string? color)
    {
        if (string.IsNullOrWhiteSpace(color))
            return "Color is required";

        if (!HexColorRegex.IsMatch(color))
            return "Color must be a valid hex color (e.g. #FF5733)";

        return null;
    }

    public string? ValidateAvatarId(int avatarId)
    {
        if (avatarId < 0 || avatarId > GameConstants.MaxAvatarId)
            return $"AvatarId must be 0-{GameConstants.MaxAvatarId}";

        return null;
    }

    [GeneratedRegex(@"^[a-zA-Z0-9 \-_']+$")]
    private static partial Regex MyDisplayNameRegex();

    [GeneratedRegex(@"^#[0-9A-Fa-f]{6}$")]
    private static partial Regex MyHexColorRegex();
}
