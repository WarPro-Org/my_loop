using Microsoft.AspNetCore.Authorization;
using MyLoop.Api.Constants;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Options;
using MyLoop.Api.Services.Moderation;
using MyLoop.Api.Services.Moderation.Alerts;

namespace MyLoop.Api.Configuration;

/// <summary>Display-name moderation (DR-002b, #190): options, the Moderator policy, services and alerting.</summary>
public static class ModerationExtensions
{
    public static IServiceCollection AddMyLoopModeration(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<ModerationOptions>()
            .Bind(configuration.GetSection(ModerationOptions.SectionName))
            .Validate(o => o.IsValid(), "Moderation:ModeratorUids contains a blank UID")
            .ValidateOnStart();
        services.AddOptions<ModerationEmailOptions>()
            .Bind(configuration.GetSection(ModerationEmailOptions.SectionName))
            .Validate(o => o.IsValid(), "Moderation:Email:Host is set but Port, From or To is missing or invalid")
            .ValidateOnStart();

        services.AddSingleton<IModeratorDirectory, ModeratorDirectory>();
        services.AddScoped<IAuthorizationHandler, ModeratorAuthorizationHandler>();
        services.AddAuthorizationBuilder()
            .AddPolicy(AuthorizationPolicies.Moderator, policy => policy
                .RequireAuthenticatedUser()
                .AddRequirements(new ModeratorRequirement()));

        services.AddSingleton<ModerationAlertQueue>();
        services.AddSingleton<IModerationAlerts>(sp => sp.GetRequiredService<ModerationAlertQueue>());
        services.AddHostedService<ModerationAlertDispatcher>();
        // Channels are opt-in per environment. A Slack channel is one more registration here.
        var email = configuration.GetSection(ModerationEmailOptions.SectionName).Get<ModerationEmailOptions>();
        if (email?.IsEnabled == true)
            services.AddSingleton<IModerationAlertChannel, SmtpModerationAlertChannel>();

        services.AddScoped<INameReportService, NameReportService>();
        services.AddScoped<IModerationService, ModerationService>();
        return services;
    }
}
