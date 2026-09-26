using Microsoft.Extensions.Options;

namespace MyLoop.Modules.Rules;

/// <summary>
/// Refuses to start the server when any rule is missing or nonsensical. A missing value binds to
/// 0, so "must be positive" also catches every setting left out of appsettings.json.
/// </summary>
public sealed class GameRulesValidator : IValidateOptions<GameRules>
{
    public ValidateOptionsResult Validate(string? name, GameRules rules)
    {
        var failures = new List<string>();

        void Positive(double value, string path)
        {
            if (!(value > 0)) failures.Add($"{GameRules.SectionName}:{path} must be greater than 0");
        }

        void Fraction(double value, string path)
        {
            if (!(value > 0 && value <= 1)) failures.Add($"{GameRules.SectionName}:{path} must be above 0 and at most 1");
        }

        Positive(rules.Version, nameof(rules.Version));

        Positive(rules.Loop.ClosureDistanceMeters, "Loop:ClosureDistanceMeters");
        Positive(rules.Loop.MinPoints, "Loop:MinPoints");
        Positive(rules.Loop.SkipNeighbors, "Loop:SkipNeighbors");
        Positive(rules.Loop.MinAreaSquareMeters, "Loop:MinAreaSquareMeters");

        Positive(rules.Gps.AccuracyThresholdMeters, "Gps:AccuracyThresholdMeters");

        Positive(rules.AntiCheat.MaxSpeedMetersPerSecond, "AntiCheat:MaxSpeedMetersPerSecond");
        Positive(rules.AntiCheat.MaxAverageSpeedMetersPerSecond, "AntiCheat:MaxAverageSpeedMetersPerSecond");
        Positive(rules.AntiCheat.GpsDriftMarginMeters, "AntiCheat:GpsDriftMarginMeters");
        Positive(rules.AntiCheat.MaxDistanceBetweenPointsMeters, "AntiCheat:MaxDistanceBetweenPointsMeters");
        Fraction(rules.AntiCheat.MaxSpeedViolationRate, "AntiCheat:MaxSpeedViolationRate");
        Positive(rules.AntiCheat.GpsSamplingIntervalSeconds, "AntiCheat:GpsSamplingIntervalSeconds");
        Fraction(rules.AntiCheat.DurationToleranceFactor, "AntiCheat:DurationToleranceFactor");
        Positive(rules.AntiCheat.MinBearingStdDev, "AntiCheat:MinBearingStdDev");

        CheckCombinations(rules, failures);

        return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
    }

    /// <summary>Rules that are only safe together.</summary>
    private static void CheckCombinations(GameRules rules, List<string> failures)
    {
        // The average-speed gate sits above the per-hop gate on purpose (see AntiCheatRules);
        // below it, fast runners would be rejected.
        var antiCheat = rules.AntiCheat;
        if (antiCheat.MaxAverageSpeedMetersPerSecond < antiCheat.MaxSpeedMetersPerSecond)
            failures.Add($"{GameRules.SectionName}:AntiCheat:MaxAverageSpeedMetersPerSecond must not be below MaxSpeedMetersPerSecond");
    }
}
