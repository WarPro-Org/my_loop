using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace MyLoop.Modules.Rules;

/// <summary>
/// Serves the rules validated at startup. Rules change only by redeploying with an edited
/// appsettings.json, so a single snapshot for the process lifetime is correct.
/// </summary>
public sealed class RuleSettings : IRuleSettings
{
    private readonly ClientRules _clientRules;

    public RuleSettings(IOptions<GameRules> options)
    {
        Current = options.Value;
        _clientRules = ToClientRules(Current);
        ClientRulesTag = Fingerprint(_clientRules);
    }

    public GameRules Current { get; }

    public ClientRules GetClientRules() => _clientRules;

    public string ClientRulesTag { get; }

    private static string Fingerprint(ClientRules rules)
    {
        const int tagHexLength = 16;
        var hash = SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(rules));
        return $"{rules.Version}-{Convert.ToHexStringLower(hash)[..tagHexLength]}";
    }

    private static ClientRules ToClientRules(GameRules rules) => new(
        Version: rules.Version,
        LoopClosureDistanceMeters: rules.Loop.ClosureDistanceMeters,
        MinLoopPoints: rules.Loop.MinPoints,
        LoopSkipNeighbors: rules.Loop.SkipNeighbors,
        GpsAccuracyThresholdMeters: rules.Gps.AccuracyThresholdMeters);
}
