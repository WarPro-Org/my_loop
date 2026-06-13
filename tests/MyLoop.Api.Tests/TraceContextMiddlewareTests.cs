using System.Diagnostics;
using Microsoft.AspNetCore.Http;
using MyLoop.Api.Middleware;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// The trace id is the join key between mobile reports, backend logs, and future traces,
/// so the middleware must surface the ambient <see cref="Activity"/> id exactly — and
/// degrade gracefully when no activity is present.
/// </summary>
public class TraceContextMiddlewareTests
{
    private static async Task<HttpContext> Run(HttpContext context)
    {
        var middleware = new TraceContextMiddleware(_ => Task.CompletedTask);
        await middleware.Invoke(context);
        return context;
    }

    [Fact]
    public async Task Echoes_the_ambient_w3c_trace_id()
    {
        // ASP.NET Core would normally start this from an inbound traceparent; simulate it.
        using var activity = new Activity("test-request").Start();

        var context = await Run(new DefaultHttpContext());

        Assert.Equal(
            activity.TraceId.ToString(),
            context.Response.Headers[TraceContextMiddleware.ResponseHeader]);
    }

    [Fact]
    public async Task Falls_back_to_the_connection_id_when_no_activity()
    {
        Assert.Null(Activity.Current); // no ambient activity in this test

        var context = new DefaultHttpContext { TraceIdentifier = "conn-7" };
        await Run(context);

        Assert.Equal("conn-7", context.Response.Headers[TraceContextMiddleware.ResponseHeader]);
    }
}
