namespace MyLoop.Modules.Rules;

/// <summary>
/// The rules the app is allowed to see (<c>GET /api/rules</c>). Deliberately excludes every
/// anti-cheat number so the app can't reveal them (#15). <see cref="AutoEndVehicleSpeedMetersPerSecond"/> is a walk
/// rule (FR2), not a cheat check: it sits above both anti-cheat speeds, so it reveals neither.
/// Mirrors <c>GameRules</c> in mobile/lib/shared/rules/game_rules.dart — keep field names in sync.
/// </summary>
public sealed record ClientRules(
    int Version,
    double LoopClosureDistanceMeters,
    int MinLoopPoints,
    int LoopSkipNeighbors,
    double GpsAccuracyThresholdMeters,
    double MinLoopAreaSquareMeters,
    double AutoEndVehicleSpeedMetersPerSecond,
    int AutoEndVehicleSeconds,
    double AutoEndStillRadiusMeters,
    int AutoEndStillSeconds,
    double AutoEndStillMaxWalkedMeters);
