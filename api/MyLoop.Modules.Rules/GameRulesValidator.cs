using Microsoft.Extensions.Options;

namespace MyLoop.Modules.Rules;

/// <summary>
/// Refuses to start the server when any rule is nonsensical. A missing setting is caught by
/// <see cref="GameRulesPresenceValidator"/>.
/// </summary>
internal sealed class GameRulesValidator : IValidateOptions<GameRules>
{
    // One line per setting on purpose: each limit is its own chosen number, so a setting a later FR adds gets
    // its line here with it (presence is covered for every setting by GameRulesPresenceValidator).
    // Upper limits catch a typo such as 500 instead of 50. Each sits at most 5× above the shipped
    // value (appsettings.json), so tuning still has room and a 10× slip stops startup.
    private const double MaxClosureDistanceMeters = 200;
    private const double MaxLoopPoints = 100;
    private const double MaxSkipNeighbors = 50;
    private const double MaxLoopAreaSquareMeters = 25_000;
    private const double MaxAccuracyThresholdMeters = 200;
    private const double MaxSpeedLimitMetersPerSecond = 15;
    private const double MaxDriftMarginMeters = 150;
    private const double MaxHopMeters = 300;
    private const double MaxSamplingIntervalSeconds = 25;
    private const double MaxBearingStdDevDegrees = 10;

    public ValidateOptionsResult Validate(string? name, GameRules rules)
    {
        var failures = new List<string>();

        // Written as !(in range) so NaN fails too. The upper limit rejects +Infinity, which would pass a
        // plain "greater than 0" and turn a check off; -Infinity fails "greater than 0".
        void Positive(double value, string path, double max)
        {
            if (!(value > 0 && value <= max))
                failures.Add($"{GameRules.SectionName}:{path} must be greater than 0 and at most {max}");
        }

        void NotNegative(double value, string path, double max)
        {
            if (!(value >= 0 && value <= max))
                failures.Add($"{GameRules.SectionName}:{path} must be 0 or more and at most {max}");
        }

        void Fraction(double value, string path)
        {
            if (!(value > 0 && value <= 1)) failures.Add($"{GameRules.SectionName}:{path} must be above 0 and at most 1");
        }

        // Setting paths come from the property names, so a rename can't leave a stale message.
        static string Loop(string setting) => $"{nameof(GameRules.Loop)}:{setting}";
        static string Gps(string setting) => $"{nameof(GameRules.Gps)}:{setting}";
        static string AntiCheat(string setting) => $"{nameof(GameRules.AntiCheat)}:{setting}";

        // Version only grows, one step per change, so it has no upper limit.
        if (rules.Version <= 0) failures.Add($"{GameRules.SectionName}:{nameof(rules.Version)} must be greater than 0");

        Positive(rules.Loop.ClosureDistanceMeters, Loop(nameof(LoopRules.ClosureDistanceMeters)), MaxClosureDistanceMeters);
        Positive(rules.Loop.MinPoints, Loop(nameof(LoopRules.MinPoints)), MaxLoopPoints);
        NotNegative(rules.Loop.SkipNeighbors, Loop(nameof(LoopRules.SkipNeighbors)), MaxSkipNeighbors);
        Positive(rules.Loop.MinAreaSquareMeters, Loop(nameof(LoopRules.MinAreaSquareMeters)), MaxLoopAreaSquareMeters);

        Positive(rules.Gps.AccuracyThresholdMeters, Gps(nameof(GpsRules.AccuracyThresholdMeters)), MaxAccuracyThresholdMeters);

        Positive(rules.AntiCheat.MaxSpeedMetersPerSecond, AntiCheat(nameof(AntiCheatRules.MaxSpeedMetersPerSecond)), MaxSpeedLimitMetersPerSecond);
        Positive(rules.AntiCheat.MaxAverageSpeedMetersPerSecond, AntiCheat(nameof(AntiCheatRules.MaxAverageSpeedMetersPerSecond)), MaxSpeedLimitMetersPerSecond);
        Positive(rules.AntiCheat.GpsDriftMarginMeters, AntiCheat(nameof(AntiCheatRules.GpsDriftMarginMeters)), MaxDriftMarginMeters);
        Positive(rules.AntiCheat.MaxDistanceBetweenPointsMeters, AntiCheat(nameof(AntiCheatRules.MaxDistanceBetweenPointsMeters)), MaxHopMeters);
        Fraction(rules.AntiCheat.MaxSpeedViolationRate, AntiCheat(nameof(AntiCheatRules.MaxSpeedViolationRate)));
        Positive(rules.AntiCheat.GpsSamplingIntervalSeconds, AntiCheat(nameof(AntiCheatRules.GpsSamplingIntervalSeconds)), MaxSamplingIntervalSeconds);
        Fraction(rules.AntiCheat.DurationToleranceFactor, AntiCheat(nameof(AntiCheatRules.DurationToleranceFactor)));
        Positive(rules.AntiCheat.MinBearingStdDev, AntiCheat(nameof(AntiCheatRules.MinBearingStdDev)), MaxBearingStdDevDegrees);

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
            failures.Add($"{GameRules.SectionName}:{nameof(GameRules.AntiCheat)}:{nameof(AntiCheatRules.MaxAverageSpeedMetersPerSecond)} must not be below {nameof(AntiCheatRules.MaxSpeedMetersPerSecond)}");
    }
}
