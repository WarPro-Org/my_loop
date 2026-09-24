using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Regression tests for PR #171 review round 2, finding 1: <c>GET /api/users/{id}/game-state</c>
/// scoped its rank count to <c>u.City == user.City &amp;&amp; !string.IsNullOrEmpty(u.City)</c>.
/// For a user with no City ("Skip for now" on set-home, or a failed reverse geocode) that
/// matches nobody, so every walk reported rank #1. Once #171 made the post-walk Home tile read
/// this rank, a city-less player saw a bogus #1. A city-less user is now ranked on the global
/// board, mirroring <c>LeaderboardService.BuildScopedQuery</c>'s city-scope fallback.
/// <para>
/// Docker-free: the rank is one <c>FindAsync</c> + one <c>CountAsync</c>, which the EF InMemory
/// provider evaluates the same way as Postgres. The Postgres-backed city-scope and tie cases
/// stay in <see cref="GameStateRankTests"/>.
/// </para>
/// </summary>
public class GameStateCitylessRankTests
{
    private const string Testville = "Testville";
    private const string OtherCity = "OtherCity";

    private readonly string _dbName = $"game-state-rank-{Guid.NewGuid()}";

    private AppDbContext NewDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseInMemoryDatabase(_dbName).Options);

    private static UsersController BuildController(AppDbContext db, Guid callerId)
    {
        var currentUser = new Mock<ICurrentUser>();
        currentUser.Setup(c => c.TryGetUserIdAsync()).ReturnsAsync(callerId);

        var missions = new Mock<IMissionService>();
        missions.Setup(m => m.GetTodaysMissions(It.IsAny<Guid>(), It.IsAny<DateOnly?>()))
            .ReturnsAsync([]);
        var achievements = new Mock<IAchievementService>();
        achievements.Setup(a => a.GetAllForUser(It.IsAny<Guid>())).ReturnsAsync([]);
        var territory = new Mock<ITerritoryService>();
        territory.Setup(t => t.GetExplorationStats(It.IsAny<Guid>())).ReturnsAsync([]);

        return new UsersController(
            Mock.Of<IUserService>(), Mock.Of<IValidationService>(), Mock.Of<IPushNotificationService>(),
            geocoding: null!, db, currentUser.Object,
            missions.Object, achievements.Object, territory.Object,
            NullLogger<UsersController>.Instance);
    }

    private async Task<Guid> SeedUser(string city, int hexCount)
    {
        var userId = Guid.NewGuid();
        await using var seed = NewDb();
        seed.Users.Add(new User
        {
            Id = userId, FirebaseUid = $"uid-{userId}", DisplayName = "P", Color = "#123456",
            City = city, HexCount = hexCount,
        });
        await seed.SaveChangesAsync();
        return userId;
    }

    private async Task<int> RankFor(Guid userId)
    {
        await using var db = NewDb();
        var result = await BuildController(db, userId).GetGameState(userId);
        var ok = Assert.IsType<OkObjectResult>(result);
        return (int)ok.Value!.GetType().GetProperty("Rank")!.GetValue(ok.Value)!;
    }

    [Fact]
    public async Task User_without_a_city_is_ranked_on_the_global_board_not_reported_as_first()
    {
        const string noCity = ""; // User.City's default; HomeLocation.Apply is its only writer
        await SeedUser(Testville, hexCount: 50);
        await SeedUser(OtherCity, hexCount: 30);
        await SeedUser(noCity, hexCount: 40); // another city-less player, also ahead
        await SeedUser(Testville, hexCount: 5); // behind: must not count
        var caller = await SeedUser(noCity, hexCount: 10);

        // Three users anywhere have strictly more hexes (50, 40, 30) -> global rank 4, not #1.
        Assert.Equal(4, await RankFor(caller));
    }

    [Fact]
    public async Task User_with_a_city_is_still_ranked_within_that_city_only()
    {
        await SeedUser(Testville, hexCount: 50);
        await SeedUser(OtherCity, hexCount: 1000);
        await SeedUser("", hexCount: 900);
        var caller = await SeedUser(Testville, hexCount: 10);

        // Only the one same-city user (50) is ahead; other cities and city-less users are not.
        Assert.Equal(2, await RankFor(caller));
    }
}
