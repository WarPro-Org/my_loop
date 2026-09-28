using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>FR1: the server sends exactly the shared sample the phone's tests read (tests/contracts/client_rules.json),
/// so a renamed field, or an anti-cheat number added to ClientRules (#15), fails here.</summary>
public class ContractTests
{
    private static readonly JsonSerializerOptions ApiJson = new(JsonSerializerDefaults.Web); // what MVC uses

    [Fact]
    public void Server_sends_exactly_the_shared_client_rules_sample()
    {
        var sample = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts", "client_rules.json")));
        var settings = new RuleSettings(Options.Create(new GameRules
        {
            Version = 3,
            Loop = new LoopRules { ClosureDistanceMeters = 42.5, MinPoints = 21, SkipNeighbors = 7, MinAreaSquareMeters = 5000 },
            Gps = new GpsRules { AccuracyThresholdMeters = 33.5 },
        }));

        var sent = JsonSerializer.SerializeToNode(settings.GetClientRules(), ApiJson);

        Assert.True(JsonNode.DeepEquals(sample, sent), $"sent {sent?.ToJsonString()}, sample {sample?.ToJsonString()}");
    }
}
