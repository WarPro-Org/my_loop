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
    [InlineData("xXshitXx")]           // severe term embedded
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
