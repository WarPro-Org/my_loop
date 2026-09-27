using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>FR1: rules load from configuration, and bad or missing values stop the server.</summary>
public class GameRulesTests
{
    private static IServiceProvider Build(IConfiguration configuration) =>
        new ServiceCollection().AddMyLoopRules(configuration).BuildServiceProvider();

    private static IConfiguration ShippedConfiguration() =>
        new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("shipped-appsettings.json")
            .Build();

    private static IConfiguration ShippedWith(string key, string? value)
    {
        var overrides = new Dictionary<string, string?> { [key] = value };
        return new ConfigurationBuilder()
            .AddConfiguration(ShippedConfiguration())
            .AddInMemoryCollection(overrides)
            .Build();
    }

    private static IConfiguration ShippedWithout(string key)
    {
        var kept = ShippedConfiguration().AsEnumerable().Where(entry => entry.Key != key);
        return new ConfigurationBuilder().AddInMemoryCollection(kept).Build();
    }

    /// <summary>Every setting in the shipped rules, e.g. <c>GameRules:Loop:SkipNeighbors</c> (not <c>_comment</c>).</summary>
    public static TheoryData<string> ShippedSettings()
    {
        var settings = new TheoryData<string>();
        foreach (var (key, value) in ShippedConfiguration().GetSection(GameRules.SectionName).AsEnumerable())
        {
            if (value is not null && !key.Split(':')[^1].StartsWith('_')) settings.Add(key);
        }
        return settings;
    }

    [Fact]
    public void Shipped_appsettings_rules_are_valid()
    {
        var rules = Build(ShippedConfiguration()).GetRequiredService<IRuleSettings>().Current;

        Assert.True(rules.Version >= 1);
        Assert.True(rules.Loop.ClosureDistanceMeters > 0);
        Assert.True(rules.AntiCheat.MaxSpeedMetersPerSecond > 0);
    }

    [Fact]
    public void Missing_GameRules_section_stops_startup()
    {
        var empty = new ConfigurationBuilder().Build();

        var ex = Assert.Throws<OptionsValidationException>(
            () => Build(empty).GetRequiredService<IOptions<GameRules>>().Value);

        Assert.Contains(ex.Failures, f => f.Contains("Version"));
        Assert.Contains(ex.Failures, f => f.Contains("Loop:ClosureDistanceMeters"));
    }

    [Theory]
    [InlineData("GameRules:AntiCheat:MaxSpeedMetersPerSecond", "-1", "AntiCheat:MaxSpeedMetersPerSecond")]
    [InlineData("GameRules:Loop:MinAreaSquareMeters", "0", "Loop:MinAreaSquareMeters")]
    [InlineData("GameRules:AntiCheat:MaxSpeedViolationRate", "1.5", "AntiCheat:MaxSpeedViolationRate")]
    [InlineData("GameRules:Version", "0", "Version")]
    [InlineData("GameRules:AntiCheat:GpsDriftMarginMeters", "0", "AntiCheat:GpsDriftMarginMeters")]
    [InlineData("GameRules:AntiCheat:MaxAverageSpeedMetersPerSecond", "5", "MaxAverageSpeedMetersPerSecond must not be below")]
    [InlineData("GameRules:Loop:ClosureDistanceMeters", "0", "Loop:ClosureDistanceMeters must be greater than 0")]
    [InlineData("GameRules:Loop:MinPoints", "0", "Loop:MinPoints must be greater than 0")]
    [InlineData("GameRules:Loop:SkipNeighbors", "-1", "Loop:SkipNeighbors must be 0 or more")]
    [InlineData("GameRules:Gps:AccuracyThresholdMeters", "0", "Gps:AccuracyThresholdMeters must be greater than 0")]
    [InlineData("GameRules:AntiCheat:MaxAverageSpeedMetersPerSecond", "0", "AntiCheat:MaxAverageSpeedMetersPerSecond must be greater than 0")]
    [InlineData("GameRules:AntiCheat:MaxDistanceBetweenPointsMeters", "0", "AntiCheat:MaxDistanceBetweenPointsMeters must be greater than 0")]
    [InlineData("GameRules:AntiCheat:GpsSamplingIntervalSeconds", "0", "AntiCheat:GpsSamplingIntervalSeconds must be greater than 0")]
    [InlineData("GameRules:AntiCheat:DurationToleranceFactor", "1.5", "AntiCheat:DurationToleranceFactor must be above 0 and at most 1")]
    [InlineData("GameRules:AntiCheat:MinBearingStdDev", "0", "AntiCheat:MinBearingStdDev must be greater than 0")]
    public void Invalid_value_stops_startup_and_names_the_setting(string key, string value, string expectedPath)
    {
        var ex = Assert.Throws<OptionsValidationException>(
            () => Build(ShippedWith(key, value)).GetRequiredService<IOptions<GameRules>>().Value);

        Assert.Contains(ex.Failures, f => f.Contains(expectedPath));
    }

    [Theory]
    [MemberData(nameof(ShippedSettings))]
    public void Missing_setting_stops_startup_and_names_it(string key)
    {
        var ex = Assert.Throws<OptionsValidationException>(
            () => Build(ShippedWithout(key)).GetRequiredService<IOptions<GameRules>>().Value);

        Assert.Contains($"{key} is missing", ex.Failures);
    }

    [Fact]
    public void Zero_skip_neighbors_is_allowed()
    {
        var rules = Build(ShippedWith("GameRules:Loop:SkipNeighbors", "0")).GetRequiredService<IRuleSettings>().Current;

        Assert.Equal(0, rules.Loop.SkipNeighbors);
    }

    [Fact]
    public async Task Server_refuses_to_start_with_missing_rules()
    {
        var builder = Host.CreateApplicationBuilder();
        builder.Services.AddMyLoopRules(new ConfigurationBuilder().Build());
        using var host = builder.Build();

        await Assert.ThrowsAsync<OptionsValidationException>(() => host.StartAsync());
    }
}
