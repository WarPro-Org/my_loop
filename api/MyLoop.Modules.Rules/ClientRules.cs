namespace MyLoop.Modules.Rules;

/// <summary>
/// The rules the app is allowed to see (<c>GET /api/rules</c>). Deliberately excludes every
/// anti-cheat and gap number so the app can't reveal them (#15).
/// Mirrors <c>GameRules</c> in mobile/lib/shared/rules/game_rules.dart — keep field names in sync.
/// </summary>
public sealed record ClientRules(
    int Version,
    double LoopClosureDistanceMeters,
    int MinLoopPoints,
    int LoopSkipNeighbors,
    double MinLoopAreaSquareMeters,
    double GpsAccuracyThresholdMeters,
    double AutoEndIdleMinutes,
    double AutoEndVehicleSpeedKmh,
    double AutoEndVehicleMinutes,
    int SafetyAlarmDelaySeconds);
