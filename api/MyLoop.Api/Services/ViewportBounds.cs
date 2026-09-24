using MyLoop.Api.Constants;

namespace MyLoop.Api.Services;

/// <summary>
/// Validation for a client-supplied viewport bounding box (#114 review). The ASP.NET
/// <c>double</c> binder accepts <c>NaN</c>, <c>Infinity</c> and arbitrarily large finite
/// values; any of those reaching the region-set computation used to spin a thread forever
/// (NaN defeats every comparison; at 1e16 <c>lat + step == lat</c>). A bbox is valid only
/// when all four values are finite, inside the WGS84 ranges, and min &lt;= max per axis.
/// </summary>
public static class ViewportBounds
{
    public static bool IsValid(double minLat, double minLng, double maxLat, double maxLng) =>
        IsValidLatitude(minLat) && IsValidLatitude(maxLat)
        && IsValidLongitude(minLng) && IsValidLongitude(maxLng)
        && minLat <= maxLat && minLng <= maxLng;

    // The range checks reject NaN on their own (every NaN comparison is false), and
    // ±Infinity falls outside the range; IsFinite states that intent explicitly.
    private static bool IsValidLatitude(double lat) =>
        double.IsFinite(lat)
        && lat >= GameConstants.MinLatitudeDegrees && lat <= GameConstants.MaxLatitudeDegrees;

    private static bool IsValidLongitude(double lng) =>
        double.IsFinite(lng)
        && lng >= GameConstants.MinLongitudeDegrees && lng <= GameConstants.MaxLongitudeDegrees;
}
