namespace MyLoop.Modules.Rules;

/// <summary>The Rules module's public interface. Other modules read game rules only through this.</summary>
public interface IRuleSettings
{
    /// <summary>All rules, including server-only ones. Never send this to the app.</summary>
    GameRules Current { get; }

    /// <summary>The subset the app is allowed to see.</summary>
    ClientRules GetClientRules();
}
