using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>FR1 / #15: the app gets only the rules it needs — never anti-cheat numbers.</summary>
public class ClientRulesTests
{
    private static IRuleSettings ShippedRules() =>
        new ServiceCollection()
            .AddMyLoopRules(new ConfigurationBuilder()
                .SetBasePath(AppContext.BaseDirectory)
                .AddJsonFile("shipped-appsettings.json")
                .Build())
            .BuildServiceProvider()
            .GetRequiredService<IRuleSettings>();

    [Fact]
    public void Client_rules_contain_no_anti_cheat_numbers()
    {
        // The vehicle speed is a walk rule above both anti-cheat speeds (FR2), the only speed the app may know.
        var names = typeof(ClientRules).GetProperties().Select(p => p.Name)
            .Where(n => n != nameof(ClientRules.AutoEndVehicleSpeedMetersPerSecond)).ToList();

        Assert.DoesNotContain(names, n => n.Contains("Speed"));
        Assert.DoesNotContain(names, n => n.Contains("Violation"));
        Assert.DoesNotContain(names, n => n.Contains("Drift"));
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
        Assert.Equal(server.Gps.AccuracyThresholdMeters, client.GpsAccuracyThresholdMeters);
        Assert.Equal(server.Loop.MinAreaSquareMeters, client.MinLoopAreaSquareMeters);
        Assert.Equal(server.AutoEnd.VehicleSpeedMetersPerSecond, client.AutoEndVehicleSpeedMetersPerSecond);
        Assert.Equal(server.AutoEnd.VehicleSeconds, client.AutoEndVehicleSeconds);
        Assert.Equal(server.AutoEnd.StillRadiusMeters, client.AutoEndStillRadiusMeters);
        Assert.Equal(server.AutoEnd.StillSeconds, client.AutoEndStillSeconds);
        Assert.Equal(server.AutoEnd.StillMaxWalkedMeters, client.AutoEndStillMaxWalkedMeters);
    }
}
