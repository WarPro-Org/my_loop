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

    /// <summary>The shipped rules with several <c>key=value</c> overrides, for settings that are only valid together.</summary>
    private static IConfiguration ShippedWithAll(params string[] overrides)
    {
        var values = overrides.Select(o => o.Split('=', 2)).ToDictionary(kv => kv[0], kv => (string?)kv[1]);
        return new ConfigurationBuilder()
            .AddConfiguration(ShippedConfiguration())
            .AddInMemoryCollection(values)
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
    // +Infinity would pass "greater than 0" and switch a check off (the upper limit rejects it); NaN fails every comparison.
    [InlineData("GameRules:AntiCheat:MaxSpeedMetersPerSecond", "Infinity", "AntiCheat:MaxSpeedMetersPerSecond must be greater than 0")]
    [InlineData("GameRules:Loop:ClosureDistanceMeters", "-Infinity", "Loop:ClosureDistanceMeters must be greater than 0")]
    [InlineData("GameRules:Gps:AccuracyThresholdMeters", "NaN", "Gps:AccuracyThresholdMeters must be greater than 0")]
    [InlineData("GameRules:AntiCheat:MaxSpeedViolationRate", "NaN", "AntiCheat:MaxSpeedViolationRate must be above 0")]
    // Upper limits: one step above each limit fails, so a 10× typo (500 instead of 50) stops startup.
    [InlineData("GameRules:Loop:ClosureDistanceMeters", "200.01", "Loop:ClosureDistanceMeters must be greater than 0 and at most 200")]
    [InlineData("GameRules:Loop:MinPoints", "101", "Loop:MinPoints must be greater than 0 and at most 100")]
    [InlineData("GameRules:Loop:SkipNeighbors", "51", "Loop:SkipNeighbors must be 0 or more and at most 50")]
    [InlineData("GameRules:Loop:MinAreaSquareMeters", "25000.1", "Loop:MinAreaSquareMeters must be greater than 0 and at most 25000")]
    [InlineData("GameRules:Gps:AccuracyThresholdMeters", "500", "Gps:AccuracyThresholdMeters must be greater than 0 and at most 200")]
    [InlineData("GameRules:AntiCheat:MaxSpeedMetersPerSecond", "15.01", "AntiCheat:MaxSpeedMetersPerSecond must be greater than 0 and at most 15")]
    [InlineData("GameRules:AntiCheat:MaxAverageSpeedMetersPerSecond", "15.01", "AntiCheat:MaxAverageSpeedMetersPerSecond must be greater than 0 and at most 15")]
    [InlineData("GameRules:AntiCheat:GpsDriftMarginMeters", "150.01", "AntiCheat:GpsDriftMarginMeters must be greater than 0 and at most 150")]
    [InlineData("GameRules:AntiCheat:MaxDistanceBetweenPointsMeters", "300.01", "AntiCheat:MaxDistanceBetweenPointsMeters must be greater than 0 and at most 300")]
    [InlineData("GameRules:AntiCheat:GpsSamplingIntervalSeconds", "25.01", "AntiCheat:GpsSamplingIntervalSeconds must be greater than 0 and at most 25")]
    [InlineData("GameRules:AntiCheat:MinBearingStdDev", "10.01", "AntiCheat:MinBearingStdDev must be greater than 0 and at most 10")]
    // FR2 AutoEnd: one step outside each lower and upper limit.
    [InlineData("GameRules:AutoEnd:VehicleSpeedMetersPerSecond", "0", "AutoEnd:VehicleSpeedMetersPerSecond must be greater than 0")]
    [InlineData("GameRules:AutoEnd:VehicleSpeedMetersPerSecond", "16.68", "AutoEnd:VehicleSpeedMetersPerSecond must be greater than 0 and at most 16.67")]
    [InlineData("GameRules:AutoEnd:VehicleSpeedMetersPerSecond", "Infinity", "AutoEnd:VehicleSpeedMetersPerSecond must be greater than 0")]
    [InlineData("GameRules:AutoEnd:VehicleSeconds", "59", "AutoEnd:VehicleSeconds must be at least 60 and at most 600")]
    [InlineData("GameRules:AutoEnd:VehicleSeconds", "601", "AutoEnd:VehicleSeconds must be at least 60 and at most 600")]
    [InlineData("GameRules:AutoEnd:StillRadiusMeters", "0", "AutoEnd:StillRadiusMeters must be greater than 0")]
    [InlineData("GameRules:AutoEnd:StillRadiusMeters", "300.01", "AutoEnd:StillRadiusMeters must be greater than 0 and at most 300")]
    [InlineData("GameRules:AutoEnd:StillMaxWalkedMeters", "99.99", "AutoEnd:StillMaxWalkedMeters must be at least 100 and at most 1000")]
    [InlineData("GameRules:AutoEnd:StillMaxWalkedMeters", "1000.01", "AutoEnd:StillMaxWalkedMeters must be at least 100 and at most 1000")]
    [InlineData("GameRules:AutoEnd:StillMaxWalkedMeters", "NaN", "AutoEnd:StillMaxWalkedMeters must be at least 100")]
    [InlineData("GameRules:AutoEnd:StillSeconds", "299", "AutoEnd:StillSeconds must be at least 300 and at most 1800")]
    [InlineData("GameRules:AutoEnd:StillSeconds", "1801", "AutoEnd:StillSeconds must be at least 300 and at most 1800")]
    // FR2 AutoEnd combinations: the vehicle speed above both anti-cheat speeds (equal is not above), the still radius
    // at least 1.5× the GPS accuracy threshold, and the walked cap above the still radius.
    [InlineData("GameRules:AutoEnd:VehicleSpeedMetersPerSecond", "9.0", "AutoEnd:VehicleSpeedMetersPerSecond must be higher than AntiCheat:MaxAverageSpeedMetersPerSecond")]
    [InlineData("GameRules:AutoEnd:VehicleSpeedMetersPerSecond", "8.33", "AutoEnd:VehicleSpeedMetersPerSecond must be higher than AntiCheat:MaxSpeedMetersPerSecond")]
    [InlineData("GameRules:AntiCheat:MaxAverageSpeedMetersPerSecond", "9.73", "AutoEnd:VehicleSpeedMetersPerSecond must be higher than AntiCheat:MaxAverageSpeedMetersPerSecond")]
    [InlineData("GameRules:AutoEnd:StillRadiusMeters", "74.99", "AutoEnd:StillRadiusMeters must be 1.5 times Gps:AccuracyThresholdMeters or more")]
    [InlineData("GameRules:Gps:AccuracyThresholdMeters", "50.01", "AutoEnd:StillRadiusMeters must be 1.5 times Gps:AccuracyThresholdMeters or more")]
    public void Invalid_value_stops_startup_and_names_the_setting(string key, string value, string expectedPath)
    {
        var ex = Assert.Throws<OptionsValidationException>(
            () => Build(ShippedWith(key, value)).GetRequiredService<IOptions<GameRules>>().Value);

        Assert.Contains(ex.Failures, f => f.Contains(expectedPath));
    }

    [Theory]
    [InlineData("150")]
    [InlineData("149.99")]
    public void Walked_cap_not_above_the_still_radius_stops_startup(string walkedCap)
    {
        var configuration = ShippedWithAll(
            "GameRules:AutoEnd:StillRadiusMeters=150", $"GameRules:AutoEnd:StillMaxWalkedMeters={walkedCap}");

        var ex = Assert.Throws<OptionsValidationException>(
            () => Build(configuration).GetRequiredService<IOptions<GameRules>>().Value);

        Assert.Contains(ex.Failures, f => f.Contains("AutoEnd:StillMaxWalkedMeters must be higher than StillRadiusMeters"));
    }

    /// <summary>
    /// Every number setting has its own value check (audit S4), so a later setting can't skip one: a negative value
    /// fails with a message from that setting's own range check ("at most"), not only from a combination check.
    /// Version is the one setting with no upper limit, because it only grows.
    /// </summary>
    [Theory]
    [MemberData(nameof(ShippedSettings))]
    public void Every_setting_has_its_own_value_check(string key)
    {
        var ex = Assert.Throws<OptionsValidationException>(
            () => Build(ShippedWith(key, "-1")).GetRequiredService<IOptions<GameRules>>().Value);

        var ownCheck = key == $"{GameRules.SectionName}:{nameof(GameRules.Version)}" ? "must be greater than 0" : "at most";
        Assert.Contains(ex.Failures, f => f.StartsWith($"{key} must") && f.Contains(ownCheck));
    }

    [Theory]
    [MemberData(nameof(ShippedSettings))]
    public void Missing_setting_stops_startup_and_names_it(string key)
    {
        var ex = Assert.Throws<OptionsValidationException>(
            () => Build(ShippedWithout(key)).GetRequiredService<IOptions<GameRules>>().Value);

        Assert.Contains($"{key} is missing", ex.Failures);
    }

    [Theory]
    [InlineData("GameRules:Loop:ClosureDistanceMeters", "200")]
    [InlineData("GameRules:Loop:MinPoints", "100")]
    [InlineData("GameRules:Loop:MinAreaSquareMeters", "25000")]
    // The still radius must be at least 1.5× the accuracy threshold and the walked cap above the radius (FR2).
    [InlineData("GameRules:Gps:AccuracyThresholdMeters", "200",
        "GameRules:AutoEnd:StillRadiusMeters=300", "GameRules:AutoEnd:StillMaxWalkedMeters=1000")]
    // The vehicle speed must stay above the anti-cheat speeds (FR2).
    [InlineData("GameRules:AntiCheat:MaxAverageSpeedMetersPerSecond", "15", "GameRules:AutoEnd:VehicleSpeedMetersPerSecond=16.67")]
    [InlineData("GameRules:AntiCheat:GpsDriftMarginMeters", "150")]
    [InlineData("GameRules:AntiCheat:MaxDistanceBetweenPointsMeters", "300")]
    [InlineData("GameRules:AntiCheat:GpsSamplingIntervalSeconds", "25")]
    [InlineData("GameRules:AntiCheat:MinBearingStdDev", "10")]
    [InlineData("GameRules:Loop:SkipNeighbors", "50")]
    [InlineData("GameRules:AutoEnd:VehicleSpeedMetersPerSecond", "16.67")]
    [InlineData("GameRules:AutoEnd:VehicleSeconds", "600")]
    [InlineData("GameRules:AutoEnd:StillRadiusMeters", "300", "GameRules:AutoEnd:StillMaxWalkedMeters=300.01")]
    [InlineData("GameRules:AutoEnd:StillMaxWalkedMeters", "1000")]
    [InlineData("GameRules:AutoEnd:StillSeconds", "1800")]
    public void Value_at_its_upper_limit_is_allowed(string key, string value, params string[] alsoSet)
    {
        var configuration = ShippedWithAll([$"{key}={value}", .. alsoSet]);

        Assert.NotNull(Build(configuration).GetRequiredService<IRuleSettings>().Current);
    }

    [Theory]
    [InlineData("GameRules:AutoEnd:VehicleSeconds", "60")]
    [InlineData("GameRules:AutoEnd:StillMaxWalkedMeters", "100")]
    [InlineData("GameRules:AutoEnd:StillSeconds", "300")]
    // Exactly 1.5× the accuracy threshold, as shipped (75 = 1.5 × 50).
    [InlineData("GameRules:AutoEnd:StillRadiusMeters", "75")]
    public void Value_at_its_lower_limit_is_allowed(string key, string value)
    {
        Assert.NotNull(Build(ShippedWith(key, value)).GetRequiredService<IRuleSettings>().Current);
    }

    [Theory]
    [InlineData("GameRules:Loop:ClosureDistanceMeters", "fifty")]
    [InlineData("GameRules:Loop:MinPoints", "20.5")]
    [InlineData("GameRules:Loop:ClosureDistanceMeters", "")]
    [InlineData("GameRules:Loop:MinPoints", "")]
    [InlineData("GameRules:AutoEnd:VehicleSeconds", "180.5")]
    [InlineData("GameRules:AutoEnd:StillSeconds", "600.5")]
    public async Task Wrong_type_or_empty_value_stops_startup(string key, string value)
    {
        var builder = Host.CreateApplicationBuilder();
        builder.Services.AddMyLoopRules(ShippedWith(key, value));
        using var host = builder.Build();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => host.StartAsync());

        Assert.Contains($"Failed to convert configuration value '{value}' at '{key}'", ex.Message);
    }

    [Fact]
    public async Task Rules_are_built_while_the_server_starts_not_on_first_request()
    {
        var builder = Host.CreateApplicationBuilder();
        builder.Services.AddMyLoopRules(ShippedConfiguration());
        // Stands in for anything that fails only while the rules are built; added last, so it wins.
        builder.Services.AddSingleton<IRuleSettings>(_ => throw new InvalidOperationException("rules failed to build"));
        using var host = builder.Build();

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => host.StartAsync());

        Assert.Equal("rules failed to build", ex.Message);
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
