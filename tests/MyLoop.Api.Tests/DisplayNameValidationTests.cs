using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// DR-002a / #189: the name regex was ASCII-only, so José, Müller, Łukasz — and O’Brien typed
/// on an iPhone (smart apostrophe U+2019) — were refused. Names must accept Latin script
/// only, and every accepted name must have exactly one stored spelling.
/// </summary>
public class DisplayNameValidationTests
{
    private readonly ValidationService _validation = new();

    [Theory]
    [InlineData("Ravi")]
    [InlineData("José")]
    [InlineData("Zoë")]
    [InlineData("François")]
    [InlineData("Müller")]
    [InlineData("Straße")]
    [InlineData("Łukasz")]
    [InlineData("Søren Ødegård")]
    [InlineData("Ștefan")]          // Romanian comma-below, Latin Extended-B
    [InlineData("Çağrı Işık")]      // Turkish dotless ı
    [InlineData("Nguyễn")]          // Latin Extended Additional
    [InlineData("Jean-Luc_2")]
    [InlineData("O'Brien")]
    [InlineData("O’Brien")]    // iOS smart apostrophe
    [InlineData("José")]      // decomposed é — NFC makes it valid
    public void Latin_names_are_accepted(string name) =>
        Assert.Null(_validation.ValidateDisplayName(name));

    [Theory]
    [InlineData("Аdmin")]      // Cyrillic А look-alike
    [InlineData("Αλέξης")]          // Greek
    [InlineData("रवि")]
    [InlineData("陈伟")]
    [InlineData("Ali×2")]           // × is in Latin-1 but not a letter
    [InlineData("Ann÷")]
    [InlineData("Hi\u01C3\u01C3\u01C3")] // ǃ is a Unicode letter that reads as "!"
    [InlineData("Adm\u01C0n")]          // ǀ reads as "|"
    [InlineData("Zé́́")] // stacked combining marks survive NFC
    [InlineData("Bob😀")]
    [InlineData("Bob.")]
    [InlineData("A")]
    [InlineData("Abcdefghijklmnopqrstu")] // 21 chars
    [InlineData("Bo\uD800b")]       // lone surrogate — Normalize would throw
    [InlineData("   ")]
    [InlineData(null)]
    public void Non_latin_or_malformed_names_are_rejected(string? name) =>
        Assert.NotNull(_validation.ValidateDisplayName(name));

    [Fact]
    public void Twenty_composed_characters_fit_even_when_sent_decomposed()
    {
        // 20 visible é's sent as e + U+0301 is 40 UTF-16 units; NFC brings it back to 20.
        var decomposed = string.Concat(Enumerable.Repeat("é", 20));
        Assert.Null(_validation.ValidateDisplayName(decomposed));
    }

    [Theory]
    [InlineData("  José  ", "José")]
    [InlineData("José", "José")]
    [InlineData("O’Brien", "O'Brien")]
    public void Normalize_produces_one_canonical_spelling(string input, string expected)
    {
        var normalized = ValidationService.NormalizeDisplayName(input);
        Assert.Equal(expected, normalized);
        Assert.Equal(expected.Length, normalized.Length); // precomposed, not e + U+0301
    }
}
