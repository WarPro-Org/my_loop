using System.Text.Json;
using System.Text.RegularExpressions;
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
    [InlineData("4dmin2")]             // leetspeak plus a trailing digit
    [InlineData("2Admin")]             // leading digits
    [InlineData("M0derator1")]         // leetspeak inside, digit after
    [InlineData("xXAdminXx")]          // gamer-tag x wrapper
    [InlineData("MyLoopSupport")]      // brand anywhere
    [InlineData("s-h-i-t")]            // single letters joined back into the word they spell
    [InlineData("f u c k")]
    [InlineData("F-u-c-k Face")]       // a spelled-out run next to an ordinary word
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
    [InlineData("N igger")]            // #193 review: one space splitting a severe term
    [InlineData("F uck")]
    [InlineData("Fuc K")]
    [InlineData("Nig Ger")]            // two non-letter halves that spell a severe term exactly
    [InlineData("B itch")]
    [InlineData("N1g G3r")]
    [InlineData("S hit")]              // letter + rest of a whole-word term
    [InlineData("Shi T")]
    [InlineData("Fa G")]
    [InlineData("N iggerboy")]         // a long severe term crossing the letter/word space
    [InlineData("Nazi1")]              // #193 review: whole-word tier with digits trimmed
    [InlineData("Fag1")]
    [InlineData("Coon2")]
    [InlineData("Anal2")]
    [InlineData("Semen2")]
    [InlineData("2Nazi")]
    [InlineData("xXnaziXx")]           // whole-word tier inside an x wrapper
    [InlineData("xXcoonXx")]
    [InlineData("KKK")]                // hand-added whole-word term
    [InlineData("K-K-K")]
    [InlineData("Fu2ck")]              // #193 review round 4: a digit leetspeak leaves unmapped
    [InlineData("F2uck")]              // (2, 6, 8, 9) splitting a term inside a word
    [InlineData("Nig9ger")]
    [InlineData("Na2zi")]              // whole-word tier read with the digit removed
    [InlineData("F-2-u-c-k")]          // digit inside a spelled-out run
    [InlineData("Bullshit")]           // common compounds of whole-word-only terms
    [InlineData("Shithead")]
    [InlineData("Shitface")]
    [InlineData("Shithole")]
    [InlineData("Horseshit")]
    [InlineData("Dipshit")]
    [InlineData("Shitbag")]
    [InlineData("Dumbass")]
    [InlineData("Asshat")]
    [InlineData("Asswipe")]
    [InlineData("Douchebag")]
    [InlineData("Big Bullsh1t")]
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
    [InlineData("Max")]                // x at one end only is not a wrapper
    [InlineData("Rex")]
    [InlineData("Xander")]
    [InlineData("Joe Root")]           // Root is an ordinary surname; not a reserved word
    [InlineData("Thomas Lutz")]        // #193 review: severe terms are matched per word, so a
    [InlineData("Margaret Ardern")]    // first name + surname can't form one across the boundary
    [InlineData("Louisa Lopez")]       // (s+lut, retard, salope, porn, maricon)
    [InlineData("Philip Ornstein")]
    [InlineData("Mari Conti")]
    [InlineData("Ana L")]              // "an"+"al" is not a spelled-out run
    [InlineData("Jean-Luc_2")]
    [InlineData("Łukasz")]
    [InlineData("J K Lee")]            // spelled-out run "jk" next to a surname
    [InlineData("Harshit Kumar")]
    [InlineData("S Lutz")]             // initial + surname: "slut" is too short to match across
    [InlineData("S Luther")]           // the space (MinSpanningSevereTermLength)
    [InlineData("P Ornstein")]
    [InlineData("J Izzy")]
    [InlineData("Deb Allen")]          // reviewed join exceptions (build_name_blocklist.py)
    [InlineData("K Inkster")]
    [InlineData("Chin K")]
    [InlineData("Wan K")]
    [InlineData("Alex")]               // x at one end only is not a wrapper, for whole words too
    [InlineData("Xavier")]
    [InlineData("Maddox")]
    [InlineData("Max2")]
    [InlineData("K Ike")]              // initial + Ike (Igbo surname): reviewed join exception
    [InlineData("Scunthorpe2")]        // exception word still skipped with its digit removed
    [InlineData("Harshit 2")]
    [InlineData("Jean-Luc 22")]
    public void Real_names_and_innocent_words_are_accepted(string name) =>
        Assert.Null(_validation.ValidateDisplayName(name));

    public static TheoryData<string> InitialAndSurnameNames()
    {
        // #193 review: the adjacent-word rules must not refuse an initial next to a real name, in
        // either order. The generator checks the whole corpus; this pins a spread of it.
        string[] surnames =
        [
            "Kumar", "Lutz", "Luther", "Lopez", "Ardern", "Ornstein", "Conti", "Sharma", "Patel",
            "Nguyen", "Tanaka", "Fukuda", "Harshit", "Kshitij", "Root", "Hitchens", "Uckfield",
            "Iggins", "Allen", "Inkster", "Ringler", "Lumpkin", "Ana", "Ashita", "Retford",
            "Orner", "Hitomi", "Utley", "Unter", "Agata", "Uta", "Luttrell", "Orna",
        ];
        var data = new TheoryData<string>();
        foreach (var surname in surnames)
        {
            foreach (var initial in "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            {
                data.Add($"{initial} {surname}");
                data.Add($"{surname} {initial}");
            }
        }
        return data;
    }

    [Theory]
    [MemberData(nameof(InitialAndSurnameNames))]
    public void Initial_and_surname_pairs_are_accepted(string name) =>
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
    public void Spelled_out_token_length_matches_the_generator()
    {
        // The generator's safety check only covers names one word at a time, which is sound only
        // while it and the matcher agree on which short tokens get joined.
        var script = ReadRepoFile("scripts/moderation/build_name_blocklist.py");
        var match = Regex.Match(script, @"(?m)^MAX_SPELLED_OUT_TOKEN_LENGTH = (\d+)$");
        Assert.True(match.Success);
        Assert.Equal(GameConstants.MaxSpelledOutTokenLength, int.Parse(match.Groups[1].Value));
    }

    [Fact]
    public void Spanning_term_length_matches_the_generator()
    {
        // The generator checks initial + name pairs against the corpora at this length; a smaller
        // C# value would refuse pairs it never checked (S Luther -> "slut").
        var script = ReadRepoFile("scripts/moderation/build_name_blocklist.py");
        var match = Regex.Match(script, @"(?m)^MIN_SPANNING_SEVERE_TERM_LENGTH = (\d+)$");
        Assert.True(match.Success);
        Assert.Equal(GameConstants.MinSpanningSevereTermLength, int.Parse(match.Groups[1].Value));
    }

    [Fact]
    public void Join_exceptions_are_two_folded_words()
    {
        // The matcher looks pairs up as "left right"; any other shape could never match.
        var malformed = NameBlocklist.JoinExceptions
            .Where(pair => pair.Split(' ').Length != 2 || NameModeration.Fold(pair) != pair)
            .ToList();
        Assert.Empty(malformed);
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
