using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Regression tests for #139 D2. <see cref="GeocodingService"/> is registered as a typed
/// HttpClient, which makes it TRANSIENT — an <c>AddSingleton</c> that used to sit above that
/// registration was silently overridden, because the last registration wins. Its throttle and
/// caches were instance fields, so every injected copy had its own semaphore and its own
/// "last request" clock: the commented "1 req/sec Nominatim policy" enforced nothing across
/// callers, and the caches never hit between requests. That state is now static.
/// </summary>
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

    // Distinct coordinates per test: the cache is static by design, so tests in this assembly
    // would otherwise pollute each other through it.
    private const double CacheLat = 51.5111;
    private const double CacheLng = -0.1222;

    [Fact]
    public async Task A_second_instance_reuses_the_first_instances_cached_area_name()
    {
        var handler = new CountingHandler();

        // Two separate instances, exactly as transient DI hands out.
        var first = NewService(handler);
        var second = NewService(handler);

        var fromFirst = await first.GetAreaName(CacheLat, CacheLng);
        var requestsAfterFirst = handler.Requests;

        var fromSecond = await second.GetAreaName(CacheLat, CacheLng);

        Assert.Equal(fromFirst, fromSecond);
        Assert.Equal(1, requestsAfterFirst);
        Assert.Equal(1, handler.Requests); // no second network call — the cache is shared
    }

    [Fact]
    public async Task Concurrent_lookups_across_instances_are_serialized_by_one_throttle()
    {
        var handler = new CountingHandler();

        // Four distinct coordinates so nothing is served from cache — every call must go out,
        // and the shared semaphore plus the 1.1s spacing must serialize them.
        var coords = new[] { (52.10, 1.10), (52.20, 1.20), (52.30, 1.30), (52.40, 1.40) };

        var start = DateTime.UtcNow;
        await Task.WhenAll(coords.Select(c =>
            NewService(handler).GetAreaName(c.Item1, c.Item2)));
        var elapsed = DateTime.UtcNow - start;

        Assert.Equal(4, handler.Requests);
        // Per-instance throttles would let all four fire at once and finish almost immediately.
        // One shared throttle spaces them ~1.1s apart, so three gaps means at least ~3.3s.
        Assert.True(elapsed.TotalSeconds >= 3.0,
            $"expected serialized requests (>=3s for 4 calls), took {elapsed.TotalSeconds:F2}s — " +
            "the throttle is not shared across instances");
    }
}
