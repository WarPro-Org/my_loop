using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;
using Testcontainers.PostgreSql;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Regression tests for issue #109 (ML-ERR-012): the leaderboard used to recompute on every
/// client-triggered <c>POST /api/leaderboard/refresh</c> call — a full <c>TerritoryCells</c>
/// group-by any authenticated user could fire up to 120 times/min. The refresh now runs only
/// from <see cref="LeaderboardRefreshWorker"/>'s background timer.
/// </summary>
public class LeaderboardRefreshWorkerTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _pg = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    private string _conn = "";

    public async Task InitializeAsync()
    {
        await _pg.StartAsync();
        _conn = _pg.GetConnectionString();
        await using var db = NewDb();
        await db.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync() => await _pg.DisposeAsync();

    private AppDbContext NewDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(_conn).Options);

    [Fact]
    public async Task RunOnceAsync_recomputes_the_leaderboard_via_the_service_scope()
    {
        var userId = Guid.NewGuid();
        await using (var seed = NewDb())
        {
            seed.Users.Add(new User
            {
                Id = userId, FirebaseUid = $"uid-{userId}", DisplayName = "P", Color = "#111111",
            });
            var claimId = Guid.NewGuid();
            seed.Claims.Add(new Claim { Id = claimId, UserId = userId, CellCount = 1, AreaM2 = 0 });
            seed.TerritoryCells.Add(new TerritoryCell
            {
                CellId = 1, OwnerId = userId, ClaimId = claimId, ClaimedAt = DateTime.UtcNow,
                CenterLat = 12.9, CenterLng = 77.5, ParentCellId = 1, NeighborhoodId = 2,
                LastRefreshedAt = DateTime.UtcNow, DecayDays = 30,
            });
            await seed.SaveChangesAsync();
        }

        var services = new ServiceCollection();
        services.AddScoped(_ => NewDb());
        var hexGrid = new Mock<IHexGridService>();
        services.AddScoped(_ => hexGrid.Object);
        services.AddScoped<ILeaderboardService, LeaderboardService>();
        await using var provider = services.BuildServiceProvider();

        // No leaderboard entry exists yet — proves this call, not test setup, created it.
        await using (var before = NewDb())
        {
            Assert.Empty(await before.LeaderboardEntries.ToListAsync());
        }

        var playerCount = await LeaderboardRefreshWorker.RunOnceAsync(
            provider.GetRequiredService<IServiceScopeFactory>(), NullLogger.Instance);

        Assert.Equal(1, playerCount);
        await using var after = NewDb();
        var entries = await after.LeaderboardEntries.ToListAsync();
        Assert.Single(entries);
        Assert.Equal(userId, entries[0].UserId);
    }
}

/// <summary>
/// Docker-free coverage for <see cref="LeaderboardRefreshWorker"/>'s shutdown path: the host's
/// stopping token must reach <see cref="ILeaderboardService.RefreshLeaderboard"/>, otherwise a
/// run blocked on another instance's advisory lock (or a Neon cold-start retry) can't be
/// abandoned and shutdown runs into the host timeout.
/// </summary>
public class LeaderboardRefreshWorkerCancellationTests
{
    [Fact]
    public async Task RunOnceAsync_passes_the_stopping_token_through_to_the_refresh()
    {
        using var cts = new CancellationTokenSource();
        var leaderboard = new Mock<ILeaderboardService>();
        leaderboard.Setup(l => l.RefreshLeaderboard(It.IsAny<CancellationToken>())).ReturnsAsync(7);

        var services = new ServiceCollection();
        services.AddScoped(_ => leaderboard.Object);
        await using var provider = services.BuildServiceProvider();

        var playerCount = await LeaderboardRefreshWorker.RunOnceAsync(
            provider.GetRequiredService<IServiceScopeFactory>(), NullLogger.Instance, cts.Token);

        Assert.Equal(7, playerCount);
        leaderboard.Verify(l => l.RefreshLeaderboard(cts.Token), Times.Once);
    }
}
