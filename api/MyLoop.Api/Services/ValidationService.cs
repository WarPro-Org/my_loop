using System.Text.RegularExpressions;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Services;

/// <summary>
/// Centralized input validation for the API.
/// </summary>
public partial class ValidationService : IValidationService
{
    private static readonly Regex DisplayNameRegex = MyDisplayNameRegex();

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

        if (!GameConstants.PlayerColors.Contains(color))
            return "Color must be one of the player palette colors (e.g. #00D4AA)";

        return null;
    }

    public string? ValidateAvatarId(int avatarId)
    {
        if (avatarId < 0 || avatarId >= GameConstants.AvatarCount)
            return $"AvatarId must be 0-{GameConstants.AvatarCount - 1}";

        return null;
    }

    [GeneratedRegex(@"^[a-zA-Z0-9 \-_']+$")]
    private static partial Regex MyDisplayNameRegex();
}
