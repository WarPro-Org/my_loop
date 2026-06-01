using System.Collections.Concurrent;
using System.Text.Json;

namespace MyLoop.Api.Services;

/// <summary>
/// Reverse geocodes coordinates to area names using Nominatim (OpenStreetMap).
/// Results are cached in-memory since area names don't change.
/// </summary>
public class GeocodingService
{
    private readonly HttpClient _http;
    private readonly ConcurrentDictionary<string, string> _cache = new();
    private readonly SemaphoreSlim _throttle = new(1, 1); // 1 req/sec Nominatim policy
    private DateTime _lastRequest = DateTime.MinValue;

    public GeocodingService(HttpClient http)
    {
        _http = http;
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("MyLoop/1.0 (territory-game)");
    }

    /// <summary>
    /// Returns a human-readable area name for the given coordinates.
    /// Falls back to "Area" if geocoding fails.
    /// </summary>
    public async Task<string> GetAreaName(double lat, double lng)
    {
        var cacheKey = $"{lat:F4},{lng:F4}";
        if (_cache.TryGetValue(cacheKey, out var cached))
            return cached;

        await _throttle.WaitAsync();
        try
        {
            // Nominatim rate limit: 1 request per second
            var elapsed = DateTime.UtcNow - _lastRequest;
            if (elapsed.TotalMilliseconds < 1100)
                await Task.Delay(1100 - (int)elapsed.TotalMilliseconds);

            var url = $"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lng}&format=json&zoom=14&addressdetails=1";
            var response = await _http.GetAsync(url);
            _lastRequest = DateTime.UtcNow;

            if (!response.IsSuccessStatusCode)
                return CacheAndReturn(cacheKey, FallbackName(lat, lng));

            var json = await response.Content.ReadAsStringAsync();
            var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            // Try to extract: suburb > neighbourhood > city_district > city
            var name = TryExtractName(root);
            return CacheAndReturn(cacheKey, name ?? FallbackName(lat, lng));
        }
        catch
        {
            return CacheAndReturn(cacheKey, FallbackName(lat, lng));
        }
        finally
        {
            _throttle.Release();
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

    private string CacheAndReturn(string key, string value)
    {
        _cache.TryAdd(key, value);
        return value;
    }

    private static string FallbackName(double lat, double lng)
        => $"Area ({lat:F2}, {lng:F2})";
}
