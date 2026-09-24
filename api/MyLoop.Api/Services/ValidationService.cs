using System.Text;
using System.Text.RegularExpressions;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Services;

/// <summary>
/// Centralized input validation for the API.
/// </summary>
public partial class ValidationService : IValidationService
{
    private const char SmartApostrophe = '\u2019';
    private const string InvalidDisplayNameCharacters =
        "DisplayName contains invalid characters (Latin letters, numbers, spaces, hyphens, apostrophes only)";
    private static readonly Regex DisplayNameRegex = MyDisplayNameRegex();

    /// <summary>
    /// Canonical stored form of a display name: trimmed, NFC-composed (so "e" + U+0301 and
    /// "é" are one name), and with the iOS smart apostrophe U+2019 folded to ASCII '.
    /// Validate and persist this form so a name only ever has one spelling (#189).
    /// </summary>
    public static string NormalizeDisplayName(string name) =>
        name.Trim().Normalize(NormalizationForm.FormC).Replace(SmartApostrophe, '\'');

    public string? ValidateDisplayName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return "DisplayName is required";

        string normalized;
        try
        {
            normalized = NormalizeDisplayName(name);
        }
        catch (ArgumentException)
        {
            // string.Normalize throws on ill-formed UTF-16 (e.g. a lone surrogate from a raw API call).
            return InvalidDisplayNameCharacters;
        }

        if (normalized.Length < GameConstants.MinDisplayNameLength)
            return $"DisplayName must be at least {GameConstants.MinDisplayNameLength} characters";

        if (normalized.Length > GameConstants.MaxDisplayNameLength)
            return $"DisplayName must be {GameConstants.MaxDisplayNameLength} characters or less";

        if (!DisplayNameRegex.IsMatch(normalized))
            return InvalidDisplayNameCharacters;

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

    /// <summary>
    /// Latin script only (#189): ASCII, Latin-1 letters (minus × U+00D7 and ÷ U+00F7),
    /// Latin Extended-A/B (minus the click letters U+01C0–U+01C3 ǀ ǁ ǂ ǃ, which read as | || ǂ !)
    /// and Latin Extended Additional — French, German, Nordic, Polish,
    /// Czech, Romanian, Turkish, Vietnamese. Other scripts stay out so Cyrillic/Greek
    /// look-alikes ("Аdmin") cannot impersonate. Combining marks left after NFC are rejected.
    /// Mirrors displayNamePattern in mobile/lib/shared/util/display_name.dart.
    /// </summary>
    [GeneratedRegex(@"^[A-Za-z0-9\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u01BF\u01C4-\u024F\u1E00-\u1EFF \-_']+$")]
    private static partial Regex MyDisplayNameRegex();
}
