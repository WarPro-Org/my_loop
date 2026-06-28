using MyLoop.Api.Constants;
using Serilog.Context;

namespace MyLoop.Api.Middleware;

/// <summary>
/// Tags requests from the in-app mock walk simulator (#29) so their log events route to a separate
/// <c>MockLogs/</c> sink instead of polluting the real beta logs. A request is "mock" iff it carries
/// the <see cref="InfrastructureDefaults.MockRequestHeader"/> header, which the Flutter client only
/// attaches in debug builds while a simulated walk is running.
///
/// This is the ONLY place the mock header is read. It pushes a single <see cref="LogContext"/>
/// property and branches logging exclusively — no controller, service, validation, claim, or
/// persistence code inspects the header or the property — so a simulated walk exercises the exact
/// same server path (anti-cheat included) as a real one.
///
/// Registered immediately after <see cref="TraceContextMiddleware"/> and before the request-logging
/// middleware so the per-request summary line is tagged too — and ONLY outside Production (see
/// <c>RequestPipelineExtensions</c>), so a tampered release client cannot use the header to divert
/// its own request logs away from the monitored real-logs sink.
/// </summary>
public class MockLogContextMiddleware
{
    private readonly RequestDelegate _next;

    public MockLogContextMiddleware(RequestDelegate next) => _next = next;

    public async Task Invoke(HttpContext context)
    {
        if (!context.Request.Headers.ContainsKey(InfrastructureDefaults.MockRequestHeader))
        {
            await _next(context);
            return;
        }

        using (LogContext.PushProperty(InfrastructureDefaults.MockLogContextProperty, true))
        {
            await _next(context);
        }
    }
}
