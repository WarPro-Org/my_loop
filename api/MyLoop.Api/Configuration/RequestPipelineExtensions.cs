using MyLoop.Api.Constants;
using MyLoop.Api.Hubs;
using MyLoop.Api.Middleware;
using Serilog;
using Serilog.AspNetCore;
using Serilog.Events;

namespace MyLoop.Api.Configuration;

/// <summary>
/// The HTTP request pipeline and its request-logging policy. Middleware order is significant and
/// preserved exactly: trace id → request summary → CORS → auth → rate limiter → endpoints.
/// </summary>
public static class RequestPipelineExtensions
{
    public static WebApplication UseMyLoopPipeline(this WebApplication app)
    {
        // Surface the W3C trace id before anything else so even auth failures are traceable, and so
        // every request log line — including the summary below — carries it.
        app.UseMiddleware<TraceContextMiddleware>();

        // One tidy summary line per request (method, path, status, elapsed ms) enriched with the
        // caller's Firebase uid. Long-lived SignalR traffic and the health/static endpoints are
        // dropped to Verbose so they don't flood the Information-level stream.
        app.UseSerilogRequestLogging(ConfigureRequestLogging);

        app.UseCors();
        app.UseAuthentication();
        app.UseAuthorization();
        app.UseRateLimiter();

        app.MapControllers();
        app.MapHub<TerritoryHub>(ApiRoutes.TerritoryHub);
        return app;
    }

    private static void ConfigureRequestLogging(RequestLoggingOptions options)
    {
        options.EnrichDiagnosticContext = EnrichWithCaller;
        options.GetLevel = ResolveLogLevel;
    }

    private static void EnrichWithCaller(IDiagnosticContext diagnosticContext, HttpContext httpContext)
    {
        var firebaseUid =
            httpContext.User.FindFirst(FirebaseClaims.UserId)?.Value
            ?? httpContext.User.FindFirst(FirebaseClaims.Subject)?.Value;
        if (!string.IsNullOrEmpty(firebaseUid))
            diagnosticContext.Set(FirebaseClaims.EnrichedUidProperty, firebaseUid);
    }

    private static LogEventLevel ResolveLogLevel(HttpContext httpContext, double elapsed, Exception? ex)
    {
        var path = httpContext.Request.Path;
        if (ex != null || httpContext.Response.StatusCode >= 500)
            return LogEventLevel.Error;
        if (path.StartsWithSegments(ApiRoutes.HubsPrefix)
            || path == ApiRoutes.Health || path == ApiRoutes.Privacy || path == ApiRoutes.Terms)
            return LogEventLevel.Verbose;
        return LogEventLevel.Information;
    }
}
