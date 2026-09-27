using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MyLoop.Modules.Rules;

public static class RulesModuleExtensions
{
    /// <summary>Registers the Rules module. Invalid or missing rules stop the server at startup.</summary>
    public static IServiceCollection AddMyLoopRules(this IServiceCollection services, IConfiguration configuration)
    {
        var section = configuration.GetSection(GameRules.SectionName);
        services.AddOptions<GameRules>()
            .Bind(section)
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<GameRules>>(new GameRulesPresenceValidator(section));
        services.AddSingleton<IValidateOptions<GameRules>, GameRulesValidator>();
        services.AddSingleton<IRuleSettings, RuleSettings>();
        return services;
    }
}
