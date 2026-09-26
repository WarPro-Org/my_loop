using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>FR1 / #15: the app gets only the rules it needs — never anti-cheat or gap numbers.</summary>
public class ClientRulesTests
{
    private static IRuleSettings ShippedRules() =>
        new ServiceCollection()
            .AddRulesModule(new ConfigurationBuilder()
                .SetBasePath(AppContext.BaseDirectory)
                .AddJsonFile("shipped-appsettings.json")
                .Build())
            .BuildServiceProvider()
            .GetRequiredService<IRuleSettings>();

    [Fact]
    public void Client_rules_contain_no_speed_gap_or_guest_numbers()
    {
        var names = typeof(ClientRules).GetProperties().Select(p => p.Name).ToList();

        Assert.DoesNotContain(names, n => n.Contains("Speed") && !n.StartsWith("AutoEnd"));
        Assert.DoesNotContain(names, n => n.Contains("Gap"));
        Assert.DoesNotContain(names, n => n.Contains("Violation"));
        Assert.DoesNotContain(names, n => n.Contains("Guest"));
    }

    [Fact]
    public void Client_rules_carry_the_same_values_the_server_uses()
    {
        var settings = ShippedRules();
        var server = settings.Current;
        var client = settings.GetClientRules();

        Assert.Equal(server.Version, client.Version);
        Assert.Equal(server.Loop.ClosureDistanceMeters, client.LoopClosureDistanceMeters);
        Assert.Equal(server.Loop.MinPoints, client.MinLoopPoints);
        Assert.Equal(server.Loop.SkipNeighbors, client.LoopSkipNeighbors);
        Assert.Equal(server.Loop.MinAreaSquareMeters, client.MinLoopAreaSquareMeters);
        Assert.Equal(server.Gps.AccuracyThresholdMeters, client.GpsAccuracyThresholdMeters);
        Assert.Equal(server.AutoEnd.IdleMinutes, client.AutoEndIdleMinutes);
        Assert.Equal(server.SafetyAlarm.DelaySeconds, client.SafetyAlarmDelaySeconds);
    }

    [Fact]
    public void Auto_end_vehicle_speed_stays_above_the_anti_cheat_limit()
    {
        // The app learns the auto-end speed, so it must not equal or reveal the anti-cheat limit.
        var rules = ShippedRules().Current;
        var antiCheatKmh = rules.AntiCheat.MaxAverageSpeedMetersPerSecond * 3.6;

        Assert.True(rules.AutoEnd.VehicleSpeedKmh > antiCheatKmh);
    }
}
