using System.Reflection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;

namespace MyLoop.Modules.Rules;

/// <summary>
/// Refuses to start the server when any setting is missing from the <c>GameRules</c> section.
/// <see cref="GameRulesValidator"/> alone can't see this: a missing number binds to 0, and 0 is
/// valid for some settings (e.g. <c>Loop:SkipNeighbors</c>). Every property of
/// <see cref="GameRules"/> is checked, so a setting a later FR adds is covered without a change here.
/// </summary>
internal sealed class GameRulesPresenceValidator(IConfiguration section) : IValidateOptions<GameRules>
{
    public ValidateOptionsResult Validate(string? name, GameRules rules)
    {
        var missing = SettingPaths(typeof(GameRules), prefix: "")
            .Where(path => section[path] is null)
            .Select(path => $"{GameRules.SectionName}:{path} is missing")
            .ToList();
        return missing.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(missing);
    }

    /// <summary>Configuration paths of every setting, e.g. <c>Loop:SkipNeighbors</c>.</summary>
    private static IEnumerable<string> SettingPaths(Type type, string prefix) =>
        type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .SelectMany(property => IsGroup(property.PropertyType)
                ? SettingPaths(property.PropertyType, $"{prefix}{property.Name}:")
                : [$"{prefix}{property.Name}"]);

    /// <summary>A nested rules class such as <see cref="LoopRules"/>, not a single value.</summary>
    private static bool IsGroup(Type type) => type.IsClass && type != typeof(string);
}
