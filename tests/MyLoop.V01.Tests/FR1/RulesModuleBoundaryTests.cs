using MyLoop.Modules.Rules;

namespace MyLoop.V01.Tests.FR1;

/// <summary>
/// FR1 / CLAUDE.md architecture: other code reaches the Rules module only through its public
/// interface. A new public type here must be a deliberate change to this list.
/// </summary>
public class RulesModuleBoundaryTests
{
    [Fact]
    public void Rules_module_exposes_only_its_interface_and_rule_shapes()
    {
        var expected = new[]
        {
            nameof(AntiCheatRules), nameof(ClientRules), nameof(GameRules), nameof(GpsRules),
            nameof(IRuleSettings), nameof(LoopRules), nameof(RulesModuleExtensions),
        };

        var exported = typeof(IRuleSettings).Assembly.GetExportedTypes().Select(t => t.Name).Order();

        Assert.Equal(expected.Order(), exported);
    }
}
