using MyLoop.Api.Constants;

namespace MyLoop.Api.Configuration;

/// <summary>
/// CORS policy. The mobile client is native (not browser-based) and is unaffected by CORS, so we
/// allow ONLY explicitly configured browser origins and never combine a wildcard/reflected origin
/// with credentials. Configure via "Cors:AllowedOrigins".
/// </summary>
public static class CorsExtensions
{
    public static IServiceCollection AddMyLoopCors(this IServiceCollection services, IConfiguration configuration)
    {
        var corsOrigins = configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>();
        return services.AddCors(options => options.AddDefaultPolicy(policy =>
        {
            if (corsOrigins.Length > 0)
                policy.WithOrigins(corsOrigins).AllowAnyHeader().AllowAnyMethod().AllowCredentials();
            else
                policy.WithOrigins(InfrastructureDefaults.DefaultCorsOrigin).AllowAnyHeader().AllowAnyMethod();
        }));
    }
}
