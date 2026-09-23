using System.Text.RegularExpressions;
using MyLoop.Api.Constants;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// DR-001 / #188: the server validated avatarId as 0–50 and colour as any hex, while the app
/// only offers 12 avatars and 8 colours. Off-catalogue values persisted and then rendered as
/// something else (avatars clamp to the last emoji). Validation must accept exactly the
/// client catalogue — and the two sides must not drift.
/// </summary>
public class AvatarColorCatalogueTests
{
    private readonly ValidationService _validation = new();

    [Theory]
    [InlineData(0)]
    [InlineData(11)]
    public void Avatar_inside_catalogue_is_accepted(int avatarId) =>
        Assert.Null(_validation.ValidateAvatarId(avatarId));

    [Theory]
    [InlineData(-1)]
    [InlineData(12)]
    [InlineData(47)]
    [InlineData(50)]
    public void Avatar_outside_catalogue_is_rejected(int avatarId) =>
        Assert.NotNull(_validation.ValidateAvatarId(avatarId));

    public static TheoryData<string> PaletteColors() => new(GameConstants.PlayerColors);

    [Theory]
    [MemberData(nameof(PaletteColors))]
    public void Every_palette_color_is_accepted(string color) =>
        Assert.Null(_validation.ValidateColor(color));

    [Theory]
    [InlineData("#FFFFFF")] // near-invisible territory
    [InlineData("#FF5733")] // valid hex, not in palette
    [InlineData("#00d4aa")] // palette colour, wrong case — client matches case-sensitively
    [InlineData("00D4AA")]
    [InlineData("#00D4AA ")]
    [InlineData("red")]
    [InlineData("")]
    [InlineData(null)]
    public void Color_outside_palette_is_rejected(string? color) =>
        Assert.NotNull(_validation.ValidateColor(color));

    [Fact]
    public void Server_avatar_count_matches_client_catalogue()
    {
        var dart = ReadMobileFile("lib/shared/widgets/avatar_widget.dart");
        var list = ExtractConstList(dart, "avatarEmojis");
        var entries = Regex.Matches(list, @"'[^']+'").Count;

        Assert.Equal(GameConstants.AvatarCount, entries);
    }

    [Fact]
    public void Server_palette_matches_client_palette()
    {
        var dart = ReadMobileFile("lib/shared/widgets/color_picker_row.dart");
        var list = ExtractConstList(dart, "playerColors");
        var clientColors = Regex.Matches(list, @"'(#[0-9A-Fa-f]{6})'")
            .Select(m => m.Groups[1].Value)
            .ToList();

        Assert.Equal(GameConstants.PlayerColors.Count, clientColors.Count);
        Assert.True(GameConstants.PlayerColors.SetEquals(clientColors),
            $"Client palette [{string.Join(", ", clientColors)}] differs from GameConstants.PlayerColors");
    }

    private static string ExtractConstList(string dart, string name)
    {
        var match = Regex.Match(dart, $@"const\s+{name}\s*=\s*\[(.*?)\];", RegexOptions.Singleline);
        Assert.True(match.Success, $"Could not find `const {name} = [...]` in the Dart source");
        return match.Groups[1].Value;
    }

    private static string ReadMobileFile(string relativePath)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "mobile", relativePath);
            if (File.Exists(candidate)) return File.ReadAllText(candidate);
        }
        throw new FileNotFoundException($"mobile/{relativePath} not found above {AppContext.BaseDirectory}");
    }
}
