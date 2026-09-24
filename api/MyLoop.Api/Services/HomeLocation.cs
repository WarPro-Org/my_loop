using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// Applies a new home position and its reverse-geocoded place name to a <see cref="User"/>.
/// Pure (no I/O), so SetHome stays a thin controller action and the rules are testable alone.
/// </summary>
public static class HomeLocation
{
    /// <summary>
    /// Moves the user's home to (<paramref name="lat"/>, <paramref name="lng"/>) and records the
    /// place name from <paramref name="location"/>.
    /// </summary>
    /// <remarks>
    /// An empty <paramref name="location"/> means naming failed (a Nominatim error, or the bounded
    /// wait on the shared geocoding throttle timing out under ordinary load), not that the place
    /// has no name. In that case the existing place fields are kept rather than overwritten with
    /// blanks: a slightly stale name for the old home is better than erasing a good one because of
    /// a transient lookup failure. On a first-ever home set the fields are already empty, so the
    /// result is the same as before: coordinates saved, no place name.
    /// </remarks>
    public static void Apply(User user, double lat, double lng, LocationInfo location, DateTime nowUtc)
    {
        user.HomeLat = lat;
        user.HomeLng = lng;

        // WHY the cooldown is stamped even when naming failed: decay distance is measured from
        // these coordinates, and they did change. Skipping the stamp would let a caller re-home
        // repeatedly whenever geocoding is slow, defeating the anti-cheat cooldown (#84).
        user.HomeSetAt = nowUtc;

        if (location.IsEmpty) return;

        user.HomeCity = location.City;
        user.HomeState = location.State;
        user.HomeCountry = location.Country;
        user.HomeContinent = location.Continent;

        // Leaderboard scope is set once, from the first home that resolves to a place.
        if (string.IsNullOrEmpty(user.City))
            user.City = location.City;
        if (string.IsNullOrEmpty(user.Country))
            user.Country = location.Country;
    }
}
