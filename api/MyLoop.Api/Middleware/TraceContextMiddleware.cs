using System.Diagnostics;
using Serilog.Context;

namespace MyLoop.Api.Middleware;

/// <summary>
/// Surfaces the request's W3C trace id into the logs and the response so a single id ties
/// together every log line for one request — and joins to the mobile client (which propagates
/// the same id via the standard <c>traceparent</c> header) and, later, to distributed traces.
///
/// ASP.NET Core already starts an <see cref="Activity"/> per request, honouring an inbound
/// <c>traceparent</c> or minting a fresh trace id. We don't generate our own id — we adopt that
/// standard one, push <c>TraceId</c>/<c>SpanId</c> into the Serilog <see cref="LogContext"/> so
/// they enrich every line in scope, and echo the trace id back as <c>X-Trace-Id</c> so a tester
/// or dev can read it off a response and quote it in a bug report.
///
/// Registered first in the pipeline (before auth) so even rejected requests are traceable, and
/// before request-logging so the request summary line carries the trace id too.
/// </summary>
public class TraceContextMiddleware
{
    public const string ResponseHeader = "X-Trace-Id";

    private readonly RequestDelegate _next;

    public TraceContextMiddleware(RequestDelegate next) => _next = next;

    public async Task Invoke(HttpContext context)
    {
        var activity = Activity.Current;
        // Fall back to the connection-scoped id if activity tracking is ever disabled.
        var traceId = activity?.TraceId.ToString() ?? context.TraceIdentifier;

        context.Response.Headers[ResponseHeader] = traceId;

        using (LogContext.PushProperty("TraceId", traceId))
        using (LogContext.PushProperty("SpanId", activity?.SpanId.ToString()))
        {
            await _next(context);
        }
    }
}
