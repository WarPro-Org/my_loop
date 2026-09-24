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
        "system",
    }.ToFrozenSet(StringComparer.Ordinal);

    // Letters that NFD does not split into base + mark, mapped to their plain-Latin reading.
    private static readonly FrozenDictionary<char, string> ExplicitFolds = new Dictionary<char, string>
    {
        ['ł'] = "l", ['ø'] = "o", ['đ'] = "d", ['ß'] = "ss", ['æ'] = "ae", ['œ'] = "oe",
        ['ı'] = "i", ['ð'] = "d", ['þ'] = "th", ['ſ'] = "s", ['ƒ'] = "f", ['ħ'] = "h", ['ŧ'] = "t",
        ['ƀ'] = "b", ['ƶ'] = "z", ['ǥ'] = "g",
    }.ToFrozenDictionary();

    private static readonly FrozenDictionary<char, char> LeetFolds = new Dictionary<char, char>
    {
        ['0'] = 'o', ['1'] = 'i', ['3'] = 'e', ['4'] = 'a', ['5'] = 's', ['7'] = 't', ['@'] = 'a',
        ['$'] = 's',
    }.ToFrozenDictionary();

    private static readonly char[] WordSeparators = [' ', '-', '_', '\''];
    private static readonly char[] Digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    private const char XWrapper = 'x';

    /// <summary>The brand is reserved anywhere in a name ("MyLoopSupport", "TheMyLoopTeam").</summary>
    private const string ReservedBrand = "myloop";

    /// <summary>
    /// Lowercase, strip accents, map leetspeak. Input must already be
    /// <see cref="ValidationService.NormalizeDisplayName"/> output. Must stay identical to
    /// <c>fold()</c> in scripts/moderation/build_name_blocklist.py, which pre-folds the terms.
    /// </summary>
    public static string Fold(string normalizedName) => Fold(normalizedName, mapLeetspeak: true);

    /// <param name="mapLeetspeak">
    /// False keeps digits as digits, so a reserved word followed by a number ("Moderator1") can be
    /// recognised before '1' becomes 'i'.
    /// </param>
    private static string Fold(string normalizedName, bool mapLeetspeak)
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
            folded.Append(mapLeetspeak && LeetFolds.TryGetValue(c, out var plain) ? plain : c);
        }
        return folded.ToString();
    }

    /// <summary>
    /// True when the name matches the blocklist: a severe term anywhere inside one word, or a
    /// whole-word/reserved term equal to one word. Letters spelled out one at a time
    /// ("s-h-i-t", "a-s-s") are joined back into a word first. Words are never otherwise joined,
    /// so a first name and surname cannot form a term across the boundary (Thomas Lutz).
    /// </summary>
    public static bool IsBlocked(string normalizedName) =>
        IsReserved(normalizedName) || MatchesBlocklist(normalizedName);

    /// <summary>
    /// Staff impersonation: a reserved word as a whole word even with digits or leetspeak around
    /// it ("Admin2", "2Admin", "4dmin2", "M0derator1"), inside a gamer-tag x wrapper
    /// ("xXAdminXx"), or the brand anywhere ("MyLoopSupport").
    /// </summary>
    private static bool IsReserved(string normalizedName)
    {
        var words = Fold(normalizedName, mapLeetspeak: false).Split(WordSeparators, StringSplitOptions.RemoveEmptyEntries);
        if (string.Concat(words).Contains(ReservedBrand, StringComparison.Ordinal)) return true;
        return words.SelectMany(ReservedCandidates).Any(ReservedWords.Contains);
    }

    /// <summary>
    /// Readings of one word to test against <see cref="ReservedWords"/>. Digits are trimmed both
    /// before leetspeak ("Moderator1", where '1' would become 'i') and after it ("4dmin2", where
    /// '4' is the 'a').
    /// </summary>
    private static IEnumerable<string> ReservedCandidates(string word)
    {
        var trimmed = word.Trim(Digits);
        foreach (var reading in new[] { trimmed, MapLeetspeak(trimmed), MapLeetspeak(word).Trim(Digits) })
        {
            yield return reading;
            if (IsXWrapped(reading)) yield return reading.Trim(XWrapper);
        }
    }

    /// <summary>
    /// "xXAdminXx": x at BOTH ends. One-sided x is ordinary spelling (Max, Rex, Xander).
    /// </summary>
    private static bool IsXWrapped(string word) =>
        word.Length > 2 && word[0] == XWrapper && word[^1] == XWrapper;

    private static string MapLeetspeak(string foldedWord) =>
        string.Concat(foldedWord.Select(c => LeetFolds.TryGetValue(c, out var plain) ? plain : c));

    private static bool MatchesBlocklist(string normalizedName)
    {
        var words = Fold(normalizedName).Split(WordSeparators, StringSplitOptions.RemoveEmptyEntries);
        // Exception words (real names/places that contain a severe term) are skipped, so they
        // also pass inside longer names ("Scunthorpe United", "Harshit Kumar").
        var candidates = words
            .Where(w => !NameBlocklist.Exceptions.Contains(w))
            .Concat(SpelledOutRuns(words));
        return candidates.Any(c => IsWholeWordMatch(c) || ContainsSevereTerm(c));
    }

    /// <summary>
    /// Each maximal run of consecutive single-letter tokens, joined: "f u c k" becomes "fuck".
    /// Longer tokens end a run, because joining real name parts is what formed slurs across
    /// word boundaries (#193 review).
    /// </summary>
    private static IEnumerable<string> SpelledOutRuns(IEnumerable<string> words)
    {
        var run = new StringBuilder();
        foreach (var word in words)
        {
            if (word.Length <= GameConstants.MaxSpelledOutTokenLength)
            {
                run.Append(word);
                continue;
            }
            if (run.Length > 0) yield return run.ToString();
            run.Clear();
        }
        if (run.Length > 0) yield return run.ToString();
    }

    private static bool ContainsSevereTerm(string word) =>
        NameBlocklist.SevereSubstrings.Any(term => word.Contains(term, StringComparison.Ordinal));

    private static bool IsWholeWordMatch(string word) =>
        NameBlocklist.WholeWords.Contains(word) || ReservedWords.Contains(word);
}
