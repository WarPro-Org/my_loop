using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using MyLoop.Api.Constants;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Regression tests for the hazards that appear once <see cref="GeocodingService"/> is a genuine
/// process-lifetime singleton (#139 D2, review of #182). While it was accidentally transient, each
/// of these was masked by the instance dying at the end of the request:
/// <list type="number">
/// <item>a failed lookup was cached, so one 429 pinned an empty City/Country for that bucket
/// until restart and SetHome persisted the blanks into home + leaderboard scope;</item>
/// <item>concurrent lookups for the same key each queued their own Nominatim request on the now
/// shared throttle instead of reusing the first result;</item>
/// <item>request-path SetHome waited without bound behind fire-and-forget exploration geocoding.</item>
/// </list>
/// Every test builds its own instance, so nothing leaks between tests.
/// </summary>
public class GeocodingSingletonHazardTests
{
    private const string SuccessPayload =
        """{"address":{"suburb":"Testville","city":"Testopolis","country":"Testland","country_code":"gb"}}""";

    /// <summary>Counts requests and delegates each response to a per-test script.</summary>
    private sealed class ScriptedHandler(
        Func<int, HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> respond)
        : HttpMessageHandler
    {
        private int _requests;
        public int Requests => Volatile.Read(ref _requests);

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var callNumber = Interlocked.Increment(ref _requests);
            return respond(callNumber, request, cancellationToken);
        }
    }

    private static HttpResponseMessage Success() => new(HttpStatusCode.OK)
    {
        Content = new StringContent(SuccessPayload, Encoding.UTF8, "application/json"),
    };

    private static GeocodingService NewService(HttpMessageHandler handler) =>
        new(new HttpClient(handler), NullLogger<GeocodingService>.Instance);

    // ── 1. Failures are not cached ────────────────────────────────────────────

    [Fact]
    public async Task A_429_location_lookup_is_retried_on_the_next_call_not_cached()
    {
        var handler = new ScriptedHandler((call, _, _) => Task.FromResult(
            call == 1 ? new HttpResponseMessage(HttpStatusCode.TooManyRequests) : Success()));
        var service = NewService(handler);

        var failed = await service.GetLocationInfo(41.11, 2.11);
        var retried = await service.GetLocationInfo(41.11, 2.11);

        Assert.True(failed.IsEmpty);
        Assert.Equal(2, handler.Requests);
        Assert.Equal("Testopolis", retried.City);
        Assert.Equal("Testland", retried.Country);
    }

    [Fact]
    public async Task A_location_lookup_that_throws_is_retried_on_the_next_call_not_cached()
    {
        var handler = new ScriptedHandler((call, _, _) => call == 1
            ? Task.FromException<HttpResponseMessage>(new HttpRequestException("DNS failure"))
            : Task.FromResult(Success()));
        var service = NewService(handler);

        var failed = await service.GetLocationInfo(41.22, 2.22);
        var retried = await service.GetLocationInfo(41.22, 2.22);

        Assert.True(failed.IsEmpty);
        Assert.Equal(2, handler.Requests);
        Assert.Equal("Testopolis", retried.City);
    }

    [Fact]
    public async Task A_location_response_without_an_address_is_not_cached()
    {
        var handler = new ScriptedHandler((call, _, _) => Task.FromResult(call == 1
            ? new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""{"error":"Unable to geocode"}""", Encoding.UTF8, "application/json"),
            }
            : Success()));
        var service = NewService(handler);

        var failed = await service.GetLocationInfo(41.33, 2.33);
        var retried = await service.GetLocationInfo(41.33, 2.33);

        Assert.True(failed.IsEmpty);
        Assert.Equal(2, handler.Requests);
        Assert.Equal("Testopolis", retried.City);
    }

    [Fact]
    public async Task A_failed_area_lookup_returns_the_fallback_name_without_caching_it()
    {
        var handler = new ScriptedHandler((call, _, _) => Task.FromResult(
            call == 1 ? new HttpResponseMessage(HttpStatusCode.InternalServerError) : Success()));
        var service = NewService(handler);

        var failed = await service.GetAreaName(41.4444, 2.4444);
        var retried = await service.GetAreaName(41.4444, 2.4444);

        Assert.Equal(GeocodingService.FallbackName(41.4444, 2.4444), failed);
        Assert.Equal(2, handler.Requests);
        Assert.Equal("Testville", retried);
    }

    [Fact]
    public async Task A_successful_location_lookup_is_still_cached()
    {
        var handler = new ScriptedHandler((_, _, _) => Task.FromResult(Success()));
        var service = NewService(handler);

        await service.GetLocationInfo(41.55, 2.55);
        var second = await service.GetLocationInfo(41.55, 2.55);

        Assert.Equal(1, handler.Requests);
        Assert.Equal("Testopolis", second.City);
    }

    // ── 2. Concurrent same-key lookups share one request ──────────────────────

    private static async Task<HttpResponseMessage> SlowSuccess(CancellationToken ct)
    {
        await Task.Delay(TimeSpan.FromMilliseconds(200), ct);
        return Success();
    }

    [Fact]
    public async Task Concurrent_area_lookups_for_the_same_key_make_one_request()
    {
        var handler = new ScriptedHandler((_, _, ct) => SlowSuccess(ct));
        var service = NewService(handler);

        var names = await Task.WhenAll(
            service.GetAreaName(42.1111, 3.1111),
            service.GetAreaName(42.1111, 3.1111),
            service.GetAreaName(42.1111, 3.1111));

        Assert.Equal(1, handler.Requests);
        Assert.All(names, n => Assert.Equal("Testville", n));
    }

    [Fact]
    public async Task Concurrent_location_lookups_for_the_same_bucket_make_one_request()
    {
        var handler = new ScriptedHandler((_, _, ct) => SlowSuccess(ct));
        var service = NewService(handler);

        var infos = await Task.WhenAll(
            service.GetLocationInfo(42.22, 3.22),
            service.GetLocationInfo(42.22, 3.22),
            service.GetLocationInfo(42.22, 3.22));

        Assert.Equal(1, handler.Requests);
        Assert.All(infos, i => Assert.Equal("Testopolis", i.City));
    }

    // The two tests above pass with EITHER coalescing or the post-throttle cache re-check, since
    // a success is cached before the queued callers re-check. A failure is never cached, so when
    // the shared request 429s only coalescing can keep the joined callers off Nominatim: without
    // it each queued caller sends its own request once it gets the throttle.

    private static async Task<HttpResponseMessage> SlowRateLimitedThenSuccess(int call, CancellationToken ct)
    {
        if (call != 1) return Success();
        await Task.Delay(TimeSpan.FromMilliseconds(200), ct);
        return new HttpResponseMessage(HttpStatusCode.TooManyRequests);
    }

    [Fact]
    public async Task Concurrent_area_lookups_share_one_failed_request_rather_than_retrying_it()
    {
        var handler = new ScriptedHandler((call, _, ct) => SlowRateLimitedThenSuccess(call, ct));
        var service = NewService(handler);

        var names = await Task.WhenAll(
            service.GetAreaName(42.3333, 3.3333),
            service.GetAreaName(42.3333, 3.3333),
            service.GetAreaName(42.3333, 3.3333));

        Assert.Equal(1, handler.Requests);
        Assert.All(names, n => Assert.Equal(GeocodingService.FallbackName(42.3333, 3.3333), n));
    }

    [Fact]
    public async Task Concurrent_location_lookups_share_one_failed_request_rather_than_retrying_it()
    {
        var handler = new ScriptedHandler((call, _, ct) => SlowRateLimitedThenSuccess(call, ct));
        var service = NewService(handler);

        var infos = await Task.WhenAll(
            service.GetLocationInfo(42.44, 3.44),
            service.GetLocationInfo(42.44, 3.44),
            service.GetLocationInfo(42.44, 3.44));

        Assert.Equal(1, handler.Requests);
        Assert.All(infos, i => Assert.True(i.IsEmpty));
    }

    // ── 3. The request path does not wait unboundedly behind background lookups ──

    [Fact]
    public async Task Location_lookup_gives_up_on_a_busy_throttle_and_does_not_cache_the_empty_result()
    {
        var backgroundEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseBackground = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new ScriptedHandler(async (_, request, _) =>
        {
            // The area (zoom=16) request stands in for a slow background lookup holding the throttle.
            if (request.RequestUri!.Query.Contains("zoom=16"))
            {
                backgroundEntered.TrySetResult();
                await releaseBackground.Task;
            }
            return Success();
        });
        var service = NewService(handler);

        var background = service.GetAreaName(43.1111, 4.1111);
        await backgroundEntered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        var requestPath = service.GetLocationInfo(43.22, 4.22);
        var bound = TimeSpan.FromSeconds(InfrastructureDefaults.GeocodingThrottleMaxWaitSeconds + 3);
        var finished = await Task.WhenAny(requestPath, Task.Delay(bound));

        releaseBackground.TrySetResult();
        await background;

        Assert.True(finished == requestPath,
            $"request-path lookup was still waiting on the throttle after {bound.TotalSeconds}s");
        Assert.True((await requestPath).IsEmpty);
        Assert.Equal(1, handler.Requests); // the timed-out lookup never reached Nominatim

        // The timeout result was not cached: once the throttle is free the bucket resolves.
        var afterwards = await service.GetLocationInfo(43.22, 4.22);
        Assert.Equal("Testopolis", afterwards.City);
        Assert.Equal(2, handler.Requests);
    }
}
