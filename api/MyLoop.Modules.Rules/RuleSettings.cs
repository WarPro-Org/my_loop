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
    }

    public GameRules Current { get; }

    public ClientRules GetClientRules() => _clientRules;

    private static ClientRules ToClientRules(GameRules rules) => new(
        Version: rules.Version,
        LoopClosureDistanceMeters: rules.Loop.ClosureDistanceMeters,
        MinLoopPoints: rules.Loop.MinPoints,
        LoopSkipNeighbors: rules.Loop.SkipNeighbors,
        MinLoopAreaSquareMeters: rules.Loop.MinAreaSquareMeters,
        GpsAccuracyThresholdMeters: rules.Gps.AccuracyThresholdMeters,
        AutoEndIdleMinutes: rules.AutoEnd.IdleMinutes,
        AutoEndVehicleSpeedKmh: rules.AutoEnd.VehicleSpeedKmh,
        AutoEndVehicleMinutes: rules.AutoEnd.VehicleMinutes,
        SafetyAlarmDelaySeconds: rules.SafetyAlarm.DelaySeconds);
}
