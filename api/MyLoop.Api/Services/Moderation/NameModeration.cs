using System.Collections.Frozen;
using System.Globalization;
using System.Text;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Services.Moderation;

/// <summary>
/// Pure display-name blocklist matching (DR-002b, #190) — no I/O, so it can run inside
/// <see cref="ValidationService"/>. Names are folded (case, accents, leetspeak, separators)
/// before matching, so "Àdmin", "H1tl3r" and "s-h-i-t" all reach the same form.
/// </summary>
public static class NameModeration
{
    /// <summary>
    /// Staff/system words a player must not appear to be. Whole-word only, because they are
    /// ordinary syllables inside innocent names ("Badminton", "Modesty").
    /// </summary>
    private static readonly FrozenSet<string> ReservedWords = new[]
    {
        "admin", "administrator", "mod", "moderator", "official", "support", "staff", "myloop",
        "system", "root",
    }.ToFrozenSet(StringComparer.Ordinal);

    // Letters that NFD does not split into base + mark, mapped to their plain-Latin reading.
    private static readonly FrozenDictionary<char, string> ExplicitFolds = new Dictionary<char, string>
    {
        ['ł'] = "l", ['ø'] = "o", ['đ'] = "d", ['ß'] = "ss", ['æ'] = "ae", ['œ'] = "oe",
        ['ı'] = "i", ['ð'] = "d", ['þ'] = "th",
    }.ToFrozenDictionary();

    private static readonly FrozenDictionary<char, char> LeetFolds = new Dictionary<char, char>
    {
        ['0'] = 'o', ['1'] = 'i', ['3'] = 'e', ['4'] = 'a', ['5'] = 's', ['7'] = 't', ['@'] = 'a',
        ['$'] = 's',
    }.ToFrozenDictionary();

    private static readonly char[] WordSeparators = [' ', '-', '_', '\''];

    /// <summary>
    /// Lowercase, strip accents, map leetspeak. Input must already be
    /// <see cref="ValidationService.NormalizeDisplayName"/> output. Must stay identical to
    /// <c>fold()</c> in scripts/moderation/build_name_blocklist.py, which pre-folds the terms.
    /// </summary>
    public static string Fold(string normalizedName)
    {
        var lowered = new StringBuilder(normalizedName.Length);
        foreach (var c in normalizedName.ToLowerInvariant())
        {
            if (ExplicitFolds.TryGetValue(c, out var replacement)) lowered.Append(replacement);
            else lowered.Append(c);
        }

        var folded = new StringBuilder(lowered.Length);
        foreach (var c in lowered.ToString().Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            folded.Append(LeetFolds.TryGetValue(c, out var plain) ? plain : c);
        }
        return folded.ToString();
    }

    /// <summary>
    /// True when the name matches the blocklist: a severe term anywhere in the folded,
    /// separator-stripped name, or a whole-word/reserved term as a complete word (or as the
    /// whole name once separators are removed, so "my_loop" and "a-s-s" still match).
    /// </summary>
    public static bool IsBlocked(string normalizedName)
    {
        var words = Fold(normalizedName).Split(WordSeparators, StringSplitOptions.RemoveEmptyEntries);
        var joined = string.Concat(words);

        if (NameBlocklist.Exceptions.Contains(joined)) return false;
        if (IsWholeWordMatch(joined) || words.Any(IsWholeWordMatch)) return true;

        foreach (var term in NameBlocklist.SevereSubstrings)
        {
            if (joined.Contains(term, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    /// <summary>
    /// The name shown in place of a hidden one: "Player#" + the first hex digits of the user id.
    /// Stable per user and derived from data that is already public in API responses. '#' can
    /// never pass display-name validation, so no player can pick a placeholder-looking name.
    /// </summary>
    public static string PlaceholderFor(Guid userId) =>
        GameConstants.HiddenNamePrefix
        + userId.ToString("N")[..GameConstants.HiddenNameIdDigits].ToUpperInvariant();

    private static bool IsWholeWordMatch(string word) =>
        NameBlocklist.WholeWords.Contains(word) || ReservedWords.Contains(word);
}
