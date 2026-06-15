using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Configuration;

/// <summary>
/// Firebase JWT authentication. The caller is always derived from the validated token, never the
/// request body. The project id comes from configuration so it is not hardcoded per environment.
/// </summary>
public static class AuthenticationExtensions
{
    public static IServiceCollection AddMyLoopAuthentication(this IServiceCollection services, IConfiguration configuration)
    {
        var projectId = configuration[InfrastructureDefaults.FirebaseProjectIdConfigKey]
            ?? InfrastructureDefaults.DefaultFirebaseProjectId;
        var authority = string.Format(InfrastructureDefaults.FirebaseAuthorityFormat, projectId);

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.Authority = authority;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = authority,
                    ValidateAudience = true,
                    ValidAudience = projectId,
                    ValidateLifetime = true,
                };
                options.Events = new JwtBearerEvents { OnMessageReceived = ForwardHubAccessToken };
            });
        services.AddAuthorization();
        return services;
    }

    // WebSocket upgrade requests can't set the Authorization header, so SignalR passes the Firebase
    // JWT via the access_token query string — accept it only for hub paths.
    private static Task ForwardHubAccessToken(MessageReceivedContext context)
    {
        var accessToken = context.Request.Query[ApiRoutes.AccessTokenQueryParam];
        var path = context.HttpContext.Request.Path;
        if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments(ApiRoutes.HubsPrefix))
            context.Token = accessToken;
        return Task.CompletedTask;
    }
}
