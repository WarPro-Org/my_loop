using System.Threading.RateLimiting;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Configuration;

/// <summary>
/// Per-user fixed-window rate limiting (falls back to client IP for anonymous callers).
/// Long-lived SignalR connections are exempt so they aren't throttled per message.
/// </summary>
public static class RateLimitingExtensions
{
    public static IServiceCollection AddMyLoopRateLimiting(this IServiceCollection services) =>
        services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ResolvePartition);
        });

    private static RateLimitPartition<string> ResolvePartition(HttpContext httpContext)
    {
        // Long-lived SignalR connections must not be throttled per-message.
        if (httpContext.Request.Path.StartsWithSegments(ApiRoutes.HubsPrefix))
            return RateLimitPartition.GetNoLimiter("hubs");

        var partitionKey =
            httpContext.User?.FindFirst("user_id")?.Value
            ?? httpContext.User?.FindFirst("sub")?.Value
            ?? httpContext.Connection.RemoteIpAddress?.ToString()
            ?? "anonymous";

        return RateLimitPartition.GetFixedWindowLimiter(partitionKey, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = InfrastructureDefaults.RateLimitPermitLimit,
            Window = TimeSpan.FromSeconds(InfrastructureDefaults.RateLimitWindowSeconds),
            QueueLimit = InfrastructureDefaults.RateLimitQueueLimit,
        });
    }
}
