using System.Text.RegularExpressions;

namespace MyLoop.Api.Services;

/// <summary>Centralized input validation for the API.</summary>
public static partial class ValidationService
{
    private static readonly Regex DisplayNameRegex = MyDisplayNameRegex();
    private static readonly Regex HexColorRegex = MyHexColorRegex();

    /// <summary>Validates a display name. Returns null if valid, error message if invalid.</summary>
    public static string? ValidateDisplayName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return "DisplayName is required";
        var trimmed = name.Trim();
        if (trimmed.Length < 2) return "DisplayName must be at least 2 characters";
        if (trimmed.Length > 20) return "DisplayName must be 20 characters or less";
        if (!DisplayNameRegex.IsMatch(trimmed)) return "DisplayName contains invalid characters (letters, numbers, spaces, hyphens only)";
        return null;
    }

    /// <summary>Validates a hex color string. Returns null if valid, error message if invalid.</summary>
    public static string? ValidateColor(string? color)
    {
        if (string.IsNullOrWhiteSpace(color)) return "Color is required";
        if (!HexColorRegex.IsMatch(color)) return "Color must be a valid hex color (e.g. #FF5733)";
        return null;
    }

    /// <summary>Validates an avatar ID. Returns null if valid, error message if invalid.</summary>
    public static string? ValidateAvatarId(int avatarId)
    {
        if (avatarId < 0 || avatarId > 50) return "AvatarId must be 0-50";
        return null;
    }

    [GeneratedRegex(@"^[a-zA-Z0-9 \-_']+$")]
    private static partial Regex MyDisplayNameRegex();

    [GeneratedRegex(@"^#[0-9A-Fa-f]{6}$")]
    private static partial Regex MyHexColorRegex();
}
