using System.Text.Json;
using MyLoop.Api.Constants;
using MyLoop.Api.Services;
using MyLoop.Api.Services.Moderation;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// DR-002b / #190: display names are public (leaderboard, map, notifications), so offensive and
/// staff-impersonating names must be refused — without refusing real people's names.
/// </summary>
public class NameModerationTests
{
    private readonly ValidationService _validation = new();

    [Theory]
    [InlineData("Hitler")]
    [InlineData("H1tl3r")]             // leetspeak
    [InlineData("xXfuckXx")]           // severe term embedded
    [InlineData("Shit")]               // whole-word tier (not substring: Harshit, Kshitij)
    [InlineData("\u017Fhit")]          // ſ (long s) folds to s
    [InlineData("\u0192uck")]          // ƒ folds to f
    [InlineData("Admin2")]             // reserved word + trailing digits
    [InlineData("Moderator1")]         // digits checked before leetspeak turns 1 into i
    [InlineData("MyLoopSupport")]      // brand anywhere
    [InlineData("s-h-i-t")]            // separators stripped before substring match
    [InlineData("Fuckface")]
    [InlineData("N1gg3r")]
    [InlineData("Arschloch")]          // German
    [InlineData("Connard")]            // French
    [InlineData("Kurwa")]              // Polish
    [InlineData("Ass")]                // whole-word tier
    [InlineData("Big Ass")]
    [InlineData("A-s-s")]              // whole-word tier matched on the joined name
    [InlineData("Nazi")]
    [InlineData("Admin")]              // reserved
    [InlineData("Àdmin")]         // accent folded: Àdmin
    [InlineData("The Admin")]
    [InlineData("Moderator 1")]
    [InlineData("my_loop")]
    [InlineData("MyLoop")]
    [InlineData("Official")]
    public void Offensive_or_reserved_names_are_rejected(string name) =>
        Assert.Equal("This name isn't allowed", _validation.ValidateDisplayName(name));

    [Theory]
    [InlineData("Badminton")]          // contains "admin" — reserved words are whole-word only
    [InlineData("Modesty")]            // contains "mod"
    [InlineData("Cassandra")]          // contains "ass"
    [InlineData("Therapist")]          // contains "rapist"
    [InlineData("Scunthorpe")]         // exception
    [InlineData("Penistone")]          // exception
    [InlineData("Hancock")]            // "cock" is whole-word only
    [InlineData("Dickens")]
    [InlineData("Francesca")]
    [InlineData("Connell")]
    [InlineData("Fischer")]
    [InlineData("Sheila")]             // contains "heil"
    [InlineData("Ignazio")]            // contains "nazi"
    [InlineData("Atwater")]            // contains "twat"
    [InlineData("Cummings")]
    [InlineData("Regina")]             // a name, dropped from the list
    [InlineData("Sega Fan")]
    [InlineData("Pipari")]             // Finnish "pepper"
    [InlineData("Harshit")]            // #193 review: South Asian names containing "shit"
    [InlineData("Rakshit Kumar")]
    [InlineData("Kshitij")]
    [InlineData("Ashita")]
    [InlineData("Fukuda")]             // Japanese names containing "fuk"
    [InlineData("Fukuoka Fan")]
    [InlineData("Scunthorpe United")]  // exception word inside a longer name
    [InlineData("Slutsky")]
    [InlineData("Sporn")]
    [InlineData("Cazzola")]
    [InlineData("Cumming")]
    [InlineData("Admiral")]            // reserved words stay whole-word
        [InlineData("Jean-Luc_2")]
    [InlineData("Łukasz")]
    public void Real_names_and_innocent_words_are_accepted(string name) =>
        Assert.Null(_validation.ValidateDisplayName(name));

    [Theory]
    [InlineData("ÀDMIN", "admin")]
    [InlineData("H1tl3r", "hitler")]
    [InlineData("Łukasz Øre", "lukasz ore")]
    [InlineData("Straße", "strasse")]
    public void Fold_lowercases_strips_accents_and_maps_leetspeak(string input, string expected) =>
        Assert.Equal(expected, NameModeration.Fold(input));

    public static TheoryData<string, string> FoldVectors()
    {
        // scripts/moderation/fold_vectors.json is also asserted by build_name_blocklist.py before it
        // generates anything, so the Python and C# folds are held to one shared table.
        var data = new TheoryData<string, string>();
        foreach (var pair in JsonSerializer.Deserialize<string[][]>(ReadRepoFile("scripts/moderation/fold_vectors.json"))!)
            data.Add(pair[0], pair[1]);
        return data;
    }

    [Theory]
    [MemberData(nameof(FoldVectors))]
    public void Fold_matches_the_shared_vectors(string input, string expected) =>
        Assert.Equal(expected, NameModeration.Fold(input));

    private static string ReadRepoFile(string relativePath)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, relativePath);
            if (File.Exists(candidate)) return File.ReadAllText(candidate);
        }
        throw new FileNotFoundException($"{relativePath} not found above {AppContext.BaseDirectory}");
    }

    [Fact]
    public void Generated_terms_are_fold_stable_so_the_script_and_the_api_agree()
    {
        // The generator pre-folds every term with its Python fold(). If the C# Fold ever diverges,
        // a term would stop matching the folded names it is compared with — this catches it.
        var terms = NameBlocklist.SevereSubstrings
            .Concat(NameBlocklist.WholeWords)
            .Concat(NameBlocklist.Exceptions);
        var unstable = terms.Where(t => NameModeration.Fold(t) != t).ToList();
        Assert.Empty(unstable);
    }

    [Fact]
    public void Placeholder_style_and_existing_ascii_names_are_not_blocked()
    {
        // Seeded/beta names must keep validating after the blocklist ships.
        foreach (var name in new[] { "Kai", "Zoe", "Alex", "Maya", "Ravi", "Priya", "Robin", "Arjun" })
            Assert.Null(_validation.ValidateDisplayName(name));
    }
}
