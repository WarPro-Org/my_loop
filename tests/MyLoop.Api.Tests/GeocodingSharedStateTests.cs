using System.Net;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using MyLoop.Api.Configuration;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Regression tests for #139 D2. <c>GeocodingService</c> was registered with
/// <c>AddSingleton</c> and then again, four lines later, via
/// <c>AddHttpClient&lt;GeocodingService&gt;</c>. The typed-client registration re-registers the type
/// as transient and the last registration wins, so the service was transient while its throttle and
/// caches were instance fields: every injection got its own semaphore and its own "last request"
/// clock, and the commented "1 req/sec Nominatim policy" enforced nothing between callers.
/// </summary>
/// <remarks>
/// These tests assert the <b>DI lifetime</b>, not static state. Making the fields static would also
/// have made the throttle process-wide, but it leaks between tests in this assembly:
/// <c>DecayNoGeocodingTests</c> proves the claim path never geocodes by throwing on coordinate
/// (12.9, 77.5), while <c>ExplorationNeighborhoodNameCacheTests</c> resolves that same coordinate
/// successfully. A shared cache would pre-warm it, so a reintroduced geocoding call would be served
/// from cache and never reach the throwing handler — that regression test would pass green while
/// shipping the exact bug it exists to catch. The lifetime is the right mechanism.
/// </remarks>
public class GeocodingSharedStateTests
{
    /// <summary>Counts requests and returns a fixed Nominatim-shaped payload.</summary>
    private sealed class CountingHandler : HttpMessageHandler
    {
        public int Requests;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref Requests);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    """{"address":{"suburb":"Testville","city":"Testopolis","country":"Testland","country_code":"gb"}}""",
                    Encoding.UTF8,
                    "application/json"),
            });
        }
    }

    private static GeocodingService NewService(CountingHandler handler) =>
        new(new HttpClient(handler), NullLogger<GeocodingService>.Instance);

    // ── The registration is what makes the throttle real ──────────────────────

    [Fact]
    public void Is_resolved_as_one_instance_so_the_throttle_is_shared()
    {
        using var provider = new ServiceCollection()
            .AddLogging()
            .AddMyLoopServices()
            .BuildServiceProvider();

        var first = provider.GetRequiredService<GeocodingService>();
        var second = provider.GetRequiredService<GeocodingService>();

        // Transient (the bug) would hand out two objects, each with its own semaphore.
        Assert.Same(first, second);
    }

    [Fact]
    public void The_same_instance_is_shared_across_request_scopes()
    {
        using var provider = new ServiceCollection()
            .AddLogging()
            .AddMyLoopServices()
            .BuildServiceProvider();

        using var scopeA = provider.CreateScope();
        using var scopeB = provider.CreateScope();

        // Two concurrent HTTP requests must not each get their own rate limiter.
        Assert.Same(
            scopeA.ServiceProvider.GetRequiredService<GeocodingService>(),
            scopeB.ServiceProvider.GetRequiredService<GeocodingService>());
    }

    // ── Given one instance, the throttle and cache behave ─────────────────────

    [Fact]
    public async Task Repeating_a_lookup_is_served_from_cache_without_a_second_request()
    {
        var handler = new CountingHandler();
        var service = NewService(handler);

        var first = await service.GetAreaName(51.5111, -0.1222);
        var second = await service.GetAreaName(51.5111, -0.1222);

        Assert.Equal(first, second);
        Assert.Equal(1, handler.Requests);
    }

    [Fact]
    public async Task Distinct_lookups_on_one_instance_are_spaced_by_the_throttle()
    {
        var handler = new CountingHandler();
        var service = NewService(handler);

        // Four distinct coordinates so none is served from cache — each must go out, and the
        // semaphore plus the ~1.1s spacing must serialize them. This is a LOWER bound, so a slow
        // or loaded CI machine can only make it pass more comfortably; it fails only if the
        // throttle is absent, which is exactly the transient-instance bug.
        var coords = new[] { (52.10, 1.10), (52.20, 1.20), (52.30, 1.30), (52.40, 1.40) };

        var start = DateTime.UtcNow;
        foreach (var (lat, lng) in coords)
            await service.GetAreaName(lat, lng);
        var elapsed = DateTime.UtcNow - start;

        Assert.Equal(4, handler.Requests);
        Assert.True(elapsed.TotalSeconds >= 3.0,
            $"expected ~1.1s spacing between 4 requests (>=3s for 3 gaps), took {elapsed.TotalSeconds:F2}s");
    }
}
