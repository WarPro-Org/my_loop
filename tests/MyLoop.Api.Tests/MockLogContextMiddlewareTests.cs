using Microsoft.AspNetCore.Http;
using MyLoop.Api.Constants;
using MyLoop.Api.Middleware;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// The mock-simulator middleware (#29) tags a request's log events with <c>IsMock</c> iff the
/// request carries the mock header — and only that. It must never tag a normal request, so real
/// beta logs stay free of synthetic-walk noise.
/// </summary>
public class MockLogContextMiddlewareTests
{
    /// <summary>Captures Serilog events emitted while the request is in flight.</summary>
    private sealed class CapturingSink : ILogEventSink
    {
        public List<LogEvent> Events { get; } = new();
        public void Emit(LogEvent logEvent) => Events.Add(logEvent);
    }

    private static async Task<LogEvent> CaptureSingleEventDuringRequest(HttpContext context)
    {
        var sink = new CapturingSink();
        var logger = new LoggerConfiguration()
            .Enrich.FromLogContext()
            .WriteTo.Sink(sink)
            .CreateLogger();

        // Logging from inside _next reproduces how controllers/services log mid-request.
        var middleware = new MockLogContextMiddleware(_ =>
        {
            logger.Information("inside the request");
            return Task.CompletedTask;
        });

        await middleware.Invoke(context);
        logger.Dispose();
        return Assert.Single(sink.Events);
    }

    [Fact]
    public async Task Tags_events_with_IsMock_when_the_mock_header_is_present()
    {
        var context = new DefaultHttpContext();
        context.Request.Headers[InfrastructureDefaults.MockRequestHeader] = "1";

        var logEvent = await CaptureSingleEventDuringRequest(context);

        Assert.True(logEvent.Properties.ContainsKey(InfrastructureDefaults.MockLogContextProperty));
    }

    [Fact]
    public async Task Does_not_tag_events_when_the_mock_header_is_absent()
    {
        var logEvent = await CaptureSingleEventDuringRequest(new DefaultHttpContext());

        Assert.False(logEvent.Properties.ContainsKey(InfrastructureDefaults.MockLogContextProperty));
    }
}
