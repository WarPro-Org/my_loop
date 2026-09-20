using MyLoop.Api.Constants;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Guards #139 D3. The API had two Haversine implementations: <see cref="GeoService"/> using
/// <see cref="GameConstants.EarthRadiusMeters"/>, and a private copy in
/// <c>PathValidationService</c> with the radius hardcoded as <c>6371000</c>. They happened to
/// agree, so consolidating changed no distance — but nothing stopped them drifting, and a
/// mismatch between the anti-cheat distance and the gameplay distance would be a subtle,
/// expensive bug. These tests pin the shared implementation's contract.
/// </summary>
public class HaversineConsolidationTests
{
    private static readonly IGeoService Geo = new GeoService();

    [Fact]
    public void Instance_and_static_entry_points_agree_exactly()
    {
        // The instance method now delegates, so any future divergence breaks here.
        foreach (var (lat1, lng1, lat2, lng2) in new[]
                 {
                     (12.9716, 77.5946, 12.9750, 77.6000), // Bangalore, ~700m
                     (51.5074, -0.1278, 48.8566, 2.3522),  // London → Paris, ~344km
                     (-33.8688, 151.2093, -33.8700, 151.2100), // Sydney, ~150m
                     (0.0, 0.0, 0.0, 0.0),                 // degenerate
                 })
        {
            Assert.Equal(
                GeoService.Haversine(lat1, lng1, lat2, lng2),
                Geo.HaversineMeters(lat1, lng1, lat2, lng2));
        }
    }

    [Fact]
    public void Uses_the_shared_earth_radius_constant_not_a_local_literal()
    {
        // Antipodal along the equator is half the great circle: pi * R. Pinning this catches a
        // reintroduced hardcoded radius, which is the specific mistake D3 describes.
        var halfCircumference = GeoService.Haversine(0, 0, 0, 180);
        Assert.Equal(Math.PI * GameConstants.EarthRadiusMeters, halfCircumference, precision: 3);
    }

    [Fact]
    public void Identical_points_are_zero_metres_apart()
    {
        Assert.Equal(0.0, GeoService.Haversine(12.9716, 77.5946, 12.9716, 77.5946), precision: 9);
    }

    [Fact]
    public void Distance_is_symmetric()
    {
        var forward = GeoService.Haversine(12.9716, 77.5946, 12.9750, 77.6000);
        var backward = GeoService.Haversine(12.9750, 77.6000, 12.9716, 77.5946);
        Assert.Equal(forward, backward, precision: 9);
    }

    [Fact]
    public void A_known_separation_is_within_a_metre_of_the_expected_distance()
    {
        // One degree of latitude at the equator is ~111.19 km on a sphere of this radius.
        var oneDegreeLat = GeoService.Haversine(0, 0, 1, 0);
        Assert.Equal(GameConstants.EarthRadiusMeters * Math.PI / 180, oneDegreeLat, precision: 3);
    }
}
