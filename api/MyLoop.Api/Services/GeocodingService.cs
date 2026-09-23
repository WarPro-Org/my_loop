using System.Collections.Concurrent;
using System.Text.Json;
using MyLoop.Api.Constants;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// Reverse geocodes coordinates to area names using Nominatim (OpenStreetMap).
/// Successful results are cached in-memory since area names don't change; failures are not.
/// </summary>
public class GeocodingService
{
    private const string UserAgent = "MyLoop/1.0 (territory-game)";
    private const string NominatimReverseUrl = "https://nominatim.openstreetmap.org/reverse";
    private const int AreaNameZoom = 16;
    private const int LocationInfoZoom = 10;

    private static readonly TimeSpan MinRequestSpacing =
        TimeSpan.FromMilliseconds(InfrastructureDefaults.GeocodingMinRequestSpacingMilliseconds);
    private static readonly TimeSpan RequestPathThrottleMaxWait =
        TimeSpan.FromSeconds(InfrastructureDefaults.GeocodingThrottleMaxWaitSeconds);

    private readonly HttpClient _http;
    private readonly ILogger<GeocodingService> _logger;

    // These are INSTANCE fields, and that is only correct because this type is registered as a
    // genuine singleton (see ServiceRegistrationExtensions.AddMyLoopServices). It previously had
    // an AddSingleton that a later AddHttpClient<GeocodingService> silently overrode — last
    // registration wins — leaving it transient, so every injection got its own semaphore and its
    // own "last request" clock. The "1 req/sec" policy enforced nothing between callers and
    // the caches never hit across requests (#139 D2).
    //
    // Deliberately NOT static. Rate limiting is process-wide, but the right mechanism for that is
    // the DI lifetime, not static state: static caches leak between xUnit tests in one assembly,
    // and DecayNoGeocodingTests asserts the claim path never geocodes by throwing on a coordinate
    // that ExplorationNeighborhoodNameCacheTests also resolves successfully. A shared cache would
    // pre-warm that coordinate and let a reintroduced geocoding call resolve from cache instead of
    // hitting the throwing handler — the regression test would pass while shipping the bug.
    //
    // The caches hold SUCCESSFUL lookups only. With a process-lifetime instance, caching a failure
    // (429, timeout, missing address) would pin an empty result for that bucket until restart, and
    // SetHome would persist those blanks into the user's home and leaderboard scope.
    //
    // The in-flight maps coalesce concurrent lookups of the same key into one Nominatim request;
    // entries are removed as soon as the lookup completes, so they never outlive a request.
    //
    // Both lookup methods share one semaphore on purpose — the policy is per-service, not per-endpoint.
    private readonly ConcurrentDictionary<string, string> _cache = new();
    private readonly ConcurrentDictionary<string, LocationInfo> _locationCache = new();
    private readonly ConcurrentDictionary<string, Lazy<Task<string>>> _areaInFlight = new();
    private readonly ConcurrentDictionary<string, Lazy<Task<LocationInfo>>> _locationInFlight = new();
    private readonly SemaphoreSlim _throttle = new(1, 1);
    private DateTime _lastRequest = DateTime.MinValue; // guarded by _throttle

    public GeocodingService(HttpClient http, ILogger<GeocodingService> logger)
    {
        _http = http;
        _logger = logger;
        _http.DefaultRequestHeaders.UserAgent.ParseAdd(UserAgent);
    }

    /// <summary>
    /// Returns a human-readable area name for the given coordinates.
    /// Falls back to <see cref="FallbackName"/> (uncached) if geocoding fails.
    /// Background-only caller, so it waits for the throttle without a bound.
    /// </summary>
    public async Task<string> GetAreaName(double lat, double lng)
    {
        var cacheKey = $"{lat:F4},{lng:F4}";
        if (_cache.TryGetValue(cacheKey, out var cached))
            return cached;

        return await CoalesceAsync(_areaInFlight, cacheKey,
            () => FetchAreaNameAsync(cacheKey, lat, lng), CancellationToken.None);
    }

    private async Task<string> FetchAreaNameAsync(string cacheKey, double lat, double lng)
    {
        await _throttle.WaitAsync();
        try
        {
            // A lookup for this key may have completed while we queued on the throttle.
            if (_cache.TryGetValue(cacheKey, out var cached))
                return cached;

            var name = await RequestAreaNameAsync(lat, lng);
            if (name is null)
                return FallbackName(lat, lng);

            _cache.TryAdd(cacheKey, name);
            return name;
        }
        finally
        {
            _throttle.Release();
        }
    }

    /// <summary>Returns the extracted area name, or null on any failure. Caller holds the throttle.</summary>
    private async Task<string?> RequestAreaNameAsync(double lat, double lng)
    {
        try
        {
            using var response = await SendSpacedAsync(ReverseUrl(lat, lng, AreaNameZoom));
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Nominatim area lookup returned {StatusCode}; using uncached fallback name",
                    (int)response.StatusCode);
                return null;
            }

            using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            return TryExtractName(doc.RootElement);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Nominatim area lookup failed; using uncached fallback name");
            return null;
        }
    }

    private static string? TryExtractName(JsonElement root)
    {
        if (!root.TryGetProperty("address", out var addr))
            return null;

        // Priority: suburb → neighbourhood → city_district → town → city
        string[] priorities = ["suburb", "neighbourhood", "city_district", "town", "city", "municipality"];
        foreach (var key in priorities)
        {
            if (addr.TryGetProperty(key, out var val))
            {
                var name = val.GetString();
                if (!string.IsNullOrWhiteSpace(name))
                    return name;
            }
        }

        // Fallback to display_name first part
        if (root.TryGetProperty("display_name", out var display))
        {
            var full = display.GetString();
            if (!string.IsNullOrEmpty(full))
                return full.Split(',')[0].Trim();
        }

        return null;
    }

    /// <summary>
    /// The "Area (lat, lng)" placeholder used when Nominatim is unreachable. Also exposed to
    /// callers (e.g. <see cref="TerritoryService.GetExplorationStats"/>) that need an immediate
    /// name without waiting on a geocode call at all.
    /// </summary>
    public static string FallbackName(double lat, double lng)
        => $"Area ({lat:F2}, {lng:F2})";

    /// <summary>
    /// Returns full location info (city, state, country) for onboarding's home lookup.
    /// Results are cached per 2-decimal coordinate bucket (~1.1km) — coarser than the
    /// area-name cache since city/state/country boundaries don't need street precision.
    /// This is on the request path, so the throttle wait is bounded by
    /// <see cref="InfrastructureDefaults.GeocodingThrottleMaxWaitSeconds"/>; on timeout or any
    /// failure an empty, uncached <see cref="LocationInfo"/> is returned.
    /// </summary>
    public async Task<LocationInfo> GetLocationInfo(
        double lat, double lng, CancellationToken cancellationToken = default)
    {
        var cacheKey = $"loc:{lat:F2},{lng:F2}";
        if (_locationCache.TryGetValue(cacheKey, out var cached))
            return cached;

        return await CoalesceAsync(_locationInFlight, cacheKey,
            () => FetchLocationInfoAsync(cacheKey, lat, lng), cancellationToken);
    }

    private async Task<LocationInfo> FetchLocationInfoAsync(string cacheKey, double lat, double lng)
    {
        // No caller token here: the lookup is shared by every coalesced caller, so one caller
        // disconnecting must not cancel it for the rest. Each caller applies its own token instead.
        if (!await _throttle.WaitAsync(RequestPathThrottleMaxWait))
        {
            _logger.LogWarning(
                "Geocoding throttle busy for {MaxWaitSeconds}s; returning uncached empty location",
                InfrastructureDefaults.GeocodingThrottleMaxWaitSeconds);
            return new LocationInfo();
        }

        try
        {
            // A lookup for this bucket may have completed while we queued on the throttle.
            if (_locationCache.TryGetValue(cacheKey, out var cached))
                return cached;

            var info = await RequestLocationInfoAsync(lat, lng);
            if (info is null)
                return new LocationInfo();

            _locationCache.TryAdd(cacheKey, info);
            return info;
        }
        finally
        {
            _throttle.Release();
        }
    }

    /// <summary>Returns the parsed location, or null on any failure. Caller holds the throttle.</summary>
    private async Task<LocationInfo?> RequestLocationInfoAsync(double lat, double lng)
    {
        try
        {
            using var response = await SendSpacedAsync(ReverseUrl(lat, lng, LocationInfoZoom));
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Nominatim location lookup returned {StatusCode}; using uncached empty location",
                    (int)response.StatusCode);
                return null;
            }

            using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            if (!doc.RootElement.TryGetProperty("address", out var addr))
            {
                _logger.LogWarning("Nominatim location lookup had no address; using uncached empty location");
                return null;
            }

            var info = new LocationInfo
            {
                City = ExtractField(addr, "city", "town", "municipality", "village"),
                State = ExtractField(addr, "state", "province", "region", "state_district"),
                Country = ExtractField(addr, "country"),
                CountryCode = ExtractField(addr, "country_code"),
            };
            info.Continent = ContinentFromCountryCode(info.CountryCode);
            return info;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Nominatim location lookup failed; using uncached empty location");
            return null;
        }
    }

    private static string ReverseUrl(double lat, double lng, int zoom)
        => $"{NominatimReverseUrl}?lat={lat}&lon={lng}&format=json&zoom={zoom}&addressdetails=1";

    /// <summary>
    /// Sends one request no sooner than <see cref="MinRequestSpacing"/> after the previous one.
    /// Caller must hold <see cref="_throttle"/>. The clock advances even when the request fails,
    /// so a timeout or 429 still counts against the policy.
    /// </summary>
    private async Task<HttpResponseMessage> SendSpacedAsync(string url)
    {
        var sinceLast = DateTime.UtcNow - _lastRequest;
        if (sinceLast < MinRequestSpacing)
            await Task.Delay(MinRequestSpacing - sinceLast);

        try
        {
            return await _http.GetAsync(url);
        }
        finally
        {
            _lastRequest = DateTime.UtcNow;
        }
    }

    /// <summary>
    /// Joins an in-flight lookup for <paramref name="key"/> or starts one, so concurrent callers for
    /// the same key share a single Nominatim request instead of each queuing their own. The entry is
    /// removed once the lookup completes (whether or not any caller is still waiting), so a failed
    /// lookup is retried by the next caller rather than remembered.
    /// </summary>
    private static Task<T> CoalesceAsync<T>(
        ConcurrentDictionary<string, Lazy<Task<T>>> inFlight,
        string key,
        Func<Task<T>> fetch,
        CancellationToken cancellationToken)
    {
        // Lazy guarantees the fetch starts once even if GetOrAdd races and builds two wrappers.
        var lookup = inFlight.GetOrAdd(key, _ => new Lazy<Task<T>>(fetch));
        var task = lookup.Value;
        _ = task.ContinueWith(
            _ => inFlight.TryRemove(new KeyValuePair<string, Lazy<Task<T>>>(key, lookup)),
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
        return task.WaitAsync(cancellationToken);
    }

    private static string ExtractField(JsonElement addr, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (addr.TryGetProperty(key, out var val))
            {
                var str = val.GetString();
                if (!string.IsNullOrWhiteSpace(str)) return str;
            }
        }
        return "";
    }

    private static string ContinentFromCountryCode(string code)
    {
        if (string.IsNullOrEmpty(code)) return "";
        code = code.ToUpperInvariant();
        // Simplified continent mapping by country code
        return code switch
        {
            "US" or "CA" or "MX" or "GT" or "BZ" or "HN" or "SV" or "NI" or "CR" or "PA"
                or "CU" or "JM" or "HT" or "DO" or "PR" or "TT" => "NA",
            "BR" or "AR" or "CO" or "VE" or "PE" or "CL" or "EC" or "BO" or "PY" or "UY"
                or "GY" or "SR" => "SA",
            "GB" or "DE" or "FR" or "IT" or "ES" or "PT" or "NL" or "BE" or "SE" or "NO"
                or "DK" or "FI" or "PL" or "CZ" or "AT" or "CH" or "IE" or "GR" or "RO"
                or "BG" or "HR" or "SK" or "HU" or "UA" or "RU" or "BY" or "LT" or "LV"
                or "EE" or "RS" or "BA" or "ME" or "MK" or "AL" or "SI" or "IS" or "LU"
                or "MT" or "CY" or "MD" or "GE" or "AM" or "AZ" => "EU",
            "IN" or "CN" or "JP" or "KR" or "ID" or "TH" or "VN" or "PH" or "MY" or "SG"
                or "BD" or "PK" or "LK" or "NP" or "MM" or "KH" or "LA" or "TW" or "HK"
                or "MO" or "MN" or "KZ" or "UZ" or "TM" or "KG" or "TJ" or "AF"
                or "IR" or "IQ" or "SA" or "AE" or "QA" or "KW" or "OM" or "YE" or "JO"
                or "LB" or "SY" or "IL" or "PS" or "BH" or "TR" => "AS",
            "AU" or "NZ" or "FJ" or "PG" or "WS" or "TO" => "OC",
            _ => "AF" // Default remaining to Africa
        };
    }
}
