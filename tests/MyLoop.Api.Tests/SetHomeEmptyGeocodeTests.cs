using System.Net;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Constants;
using MyLoop.Api.Controllers;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Regression tests for #182 round-2 review: once <see cref="GeocodingService"/> became a shared
/// singleton with a bounded throttle wait, <c>GetLocationInfo</c> returns an empty
/// <see cref="LocationInfo"/> under ordinary load, not only on a real Nominatim failure. SetHome
/// used to write those blanks over a previously good home place name. It must now keep the old
/// place fields, while still moving the coordinates and stamping the #84 cooldown.
/// <para>
/// Docker-free: SetHome only does <c>FindAsync</c> + <c>SaveChangesAsync</c> on one row, which
/// behaves the same on the EF InMemory provider as on Postgres.
/// </para>
/// </summary>
public class SetHomeEmptyGeocodeTests
{
    private const string OldCity = "Oldtown";
    private const string OldState = "Oldshire";
    private const string OldCountry = "Oldland";
    private const string OldContinent = "Europe";
    private const double OldLat = 51.5;
    private const double OldLng = -0.12;
    private const double NewLat = 48.85;
    private const double NewLng = 2.35;

    private const string SuccessPayload =
        """{"address":{"city":"Newcity","state":"Newstate","country":"Newland","country_code":"fr"}}""";

    private sealed class FixedStatusHandler(HttpStatusCode status, string? body = null) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(status)
            {
                Content = new StringContent(body ?? "", Encoding.UTF8, "application/json"),
            });
    }

    private readonly string _dbName = $"set-home-{Guid.NewGuid()}";

    private AppDbContext NewDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseInMemoryDatabase(_dbName).Options);

    private static HttpMessageHandler FailingGeocoder() => new FixedStatusHandler(HttpStatusCode.TooManyRequests);

    private static HttpMessageHandler WorkingGeocoder() => new FixedStatusHandler(HttpStatusCode.OK, SuccessPayload);

    private static UsersController BuildController(AppDbContext db, Guid callerId, HttpMessageHandler geocoder)
    {
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var geocoding = new GeocodingService(new HttpClient(geocoder), NullLogger<GeocodingService>.Instance);

        return new UsersController(
            Mock.Of<IUserService>(), Mock.Of<IValidationService>(),
            Mock.Of<IPushNotificationService>(), geocoding, db, currentUser.Object,
            Mock.Of<IMissionService>(), Mock.Of<IAchievementService>(), Mock.Of<ITerritoryService>(),
            NullLogger<UsersController>.Instance);
    }

    /// <summary>A user whose home was set (and named) long enough ago that re-homing is allowed.</summary>
    private async Task<(Guid Id, DateTime PreviousSetAt)> SeedNamedHomeOutsideCooldown()
    {
        var userId = Guid.NewGuid();
        var previousSetAt = DateTime.UtcNow.AddDays(-(GameConstants.HomeChangeCooldownDays + 1));
        await using var seed = NewDb();
        seed.Users.Add(new User
        {
            Id = userId, FirebaseUid = $"uid-{userId}", DisplayName = "H", Color = "#111111",
            HomeLat = OldLat, HomeLng = OldLng, HomeSetAt = previousSetAt,
            HomeCity = OldCity, HomeState = OldState, HomeCountry = OldCountry, HomeContinent = OldContinent,
            City = OldCity, Country = OldCountry,
        });
        await seed.SaveChangesAsync();
        return (userId, previousSetAt);
    }

    private async Task<User> LoadUser(Guid userId)
    {
        await using var check = NewDb();
        return await check.Users.SingleAsync(u => u.Id == userId);
    }

    [Fact]
    public async Task Rehome_with_empty_geocode_keeps_previous_place_fields()
    {
        var (userId, _) = await SeedNamedHomeOutsideCooldown();

        await using var db = NewDb();
        var result = await BuildController(db, userId, FailingGeocoder())
            .SetHome(userId, new SetHomeRequest { Lat = NewLat, Lng = NewLng });

        Assert.IsType<OkObjectResult>(result);
        var user = await LoadUser(userId);
        Assert.Equal(OldCity, user.HomeCity);
        Assert.Equal(OldState, user.HomeState);
        Assert.Equal(OldCountry, user.HomeCountry);
        Assert.Equal(OldContinent, user.HomeContinent);
        Assert.Equal(OldCity, user.City);
        Assert.Equal(OldCountry, user.Country);
    }

    [Fact]
    public async Task Rehome_with_empty_geocode_still_moves_coordinates_and_starts_the_cooldown()
    {
        var (userId, previousSetAt) = await SeedNamedHomeOutsideCooldown();

        await using (var db = NewDb())
        {
            Assert.IsType<OkObjectResult>(await BuildController(db, userId, FailingGeocoder())
                .SetHome(userId, new SetHomeRequest { Lat = NewLat, Lng = NewLng }));
        }

        var user = await LoadUser(userId);
        Assert.Equal(NewLat, user.HomeLat);
        Assert.Equal(NewLng, user.HomeLng);
        Assert.True(user.HomeSetAt > previousSetAt);

        // Anti-cheat #84: a failed name lookup must not be a way around the cooldown.
        await using var db2 = NewDb();
        var second = await BuildController(db2, userId, FailingGeocoder())
            .SetHome(userId, new SetHomeRequest { Lat = OldLat, Lng = OldLng });
        var status = Assert.IsType<ObjectResult>(second);
        Assert.Equal(StatusCodes.Status429TooManyRequests, status.StatusCode);
    }

    [Fact]
    public async Task First_home_with_empty_geocode_saves_coordinates_without_a_place_name()
    {
        var userId = Guid.NewGuid();
        await using (var seed = NewDb())
        {
            seed.Users.Add(new User
            {
                Id = userId, FirebaseUid = $"uid-{userId}", DisplayName = "H", Color = "#111111",
            });
            await seed.SaveChangesAsync();
        }

        await using var db = NewDb();
        Assert.IsType<OkObjectResult>(await BuildController(db, userId, FailingGeocoder())
            .SetHome(userId, new SetHomeRequest { Lat = NewLat, Lng = NewLng }));

        var user = await LoadUser(userId);
        Assert.Equal(NewLat, user.HomeLat);
        Assert.Equal("", user.HomeCity);
        Assert.Equal("", user.HomeCountry);
        Assert.Equal("", user.City);
        Assert.NotNull(user.HomeSetAt);
    }

    [Fact]
    public async Task Rehome_with_resolved_geocode_replaces_home_place_but_not_leaderboard_scope()
    {
        var (userId, _) = await SeedNamedHomeOutsideCooldown();

        await using var db = NewDb();
        Assert.IsType<OkObjectResult>(await BuildController(db, userId, WorkingGeocoder())
            .SetHome(userId, new SetHomeRequest { Lat = NewLat, Lng = NewLng }));

        var user = await LoadUser(userId);
        Assert.Equal("Newcity", user.HomeCity);
        Assert.Equal("Newstate", user.HomeState);
        Assert.Equal("Newland", user.HomeCountry);
        // Leaderboard scope is set once and never moved by a re-home (unchanged behaviour).
        Assert.Equal(OldCity, user.City);
        Assert.Equal(OldCountry, user.Country);
    }
}
