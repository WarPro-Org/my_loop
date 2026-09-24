using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Services;
using Testcontainers.PostgreSql;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Regression tests for issue #125 (ML-ERR-028):
/// (1) FetchTopEntries re-numbered ranks positionally (i+1) after scope filtering, while
///     ResolveUserRank computes count-of-higher — tied players saw different ranks depending
///     on whether they were on the top list. Both now use competition ranking ("1224").
/// (2) The snapshot was keyed to UTC-today only, so between 00:00 UTC and the day's first
///     refresh the board and the profile rank tile went blank. Both now fall back to the
///     latest committed snapshot date.
/// (BuildScopedQuery's blocking Users.Find on the async path is also gone — FindAsync.)
/// </summary>
public class LeaderboardConsistencyTests : IAsyncLifetime
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

    private static LeaderboardService NewService(AppDbContext db)
    {
        var hex = new Mock<IHexGridService>();
        hex.Setup(h => h.CalculateArea(It.IsAny<int>()))
            .Returns<int>(c => c * GameConstants.CellAreaSquareMeters);
        return new LeaderboardService(db, hex.Object);
    }

    /// <summary>Seeds a user plus a leaderboard entry for <paramref name="date"/>.</summary>
    private async Task<Guid> SeedRankedUser(int cellCount, int globalRank, DateOnly date, string city = "")
    {
        var userId = Guid.NewGuid();
        await using var seed = NewDb();
        seed.Users.Add(new User
        {
            Id = userId,
            FirebaseUid = $"uid-{userId}",
            DisplayName = $"U{globalRank}",
            Color = "#111111",
            City = city,
        });
        seed.LeaderboardEntries.Add(new LeaderboardEntry
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Date = date,
            CellCount = cellCount,
            AreaM2 = cellCount * GameConstants.CellAreaSquareMeters,
            Rank = globalRank,
        });
        await seed.SaveChangesAsync();
        return userId;
    }

    [Fact]
    public async Task Tied_players_share_a_rank_on_the_board_and_off_it()
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var first = await SeedRankedUser(100, 1, today);
        var tied = await SeedRankedUser(100, 2, today);
        var third = await SeedRankedUser(90, 3, today);

        await using var db = NewDb();
        var board = await NewService(db).GetLeaderboard(0, 0, tied, "global");

        // Competition ranking: 100, 100, 90 → ranks 1, 1, 3 — not positional 1, 2, 3.
        Assert.Equal([1, 1, 3], board.Top.Select(e => e.Rank));
        // The tied player's own rank matches what the board displays for them.
        Assert.Equal(1, board.MyRank!.Rank);

        var thirdBoard = await NewService(db).GetLeaderboard(0, 0, third, "global");
        Assert.Equal(3, thirdBoard.MyRank!.Rank);
        _ = first;
    }

    [Fact]
    public async Task City_scope_uses_the_same_rank_rule_as_MyRank()
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        await SeedRankedUser(100, 1, today, city: "X");
        await SeedRankedUser(100, 2, today, city: "X");
        var cityRival = await SeedRankedUser(90, 3, today, city: "Y");
        var me = await SeedRankedUser(60, 4, today, city: "X");

        await using var db = NewDb();
        var board = await NewService(db).GetLeaderboard(0, 0, me, "city");

        // Scoped to city X: 100, 100, 60 → ranks 1, 1, 3 (dense positional re-ranking gave
        // the second tied player rank 2, disagreeing with the count-of-higher MyRank rule).
        Assert.Equal([1, 1, 3], board.Top.Select(e => e.Rank));
        Assert.DoesNotContain(board.Top, e => e.UserId == cityRival);
        Assert.Equal(3, board.MyRank!.Rank);
    }

    [Fact]
    public async Task Blank_window_after_utc_midnight_serves_the_latest_snapshot()
    {
        // The refresh hasn't run yet "today" — only yesterday's snapshot exists.
        var yesterday = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-1);
        await SeedRankedUser(100, 1, yesterday);
        var me = await SeedRankedUser(90, 2, yesterday);

        await using var db = NewDb();
        var board = await NewService(db).GetLeaderboard(0, 0, me, "global");

        Assert.Equal(2, board.Top.Count);
        Assert.NotNull(board.MyRank);
        Assert.Equal(2, board.MyRank!.Rank);
    }

    /// <summary>
    /// #139 D7: a newcomer's seeded rank used to be the total user count, which invented a number
    /// twice over — it counted users with no row on the visible snapshot, and it gave every
    /// zero-cell player a different rank when they are tied. It must now be count-of-strictly-higher
    /// plus one, the same rule every reader applies (#167).
    /// </summary>
    [Fact]
    public async Task A_newcomers_seeded_rank_counts_only_players_ahead_of_them()
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        // Two players have captured something; one other already has zero cells.
        await SeedRankedUser(100, 1, today);
        await SeedRankedUser(90, 2, today);
        await SeedRankedUser(0, 3, today);

        // Extra users with NO row on this snapshot — the old total-count rank would have
        // included them and inflated the newcomer's position.
        await using (var noise = NewDb())
        {
            for (var i = 0; i < 5; i++)
            {
                noise.Users.Add(new User
                {
                    Id = Guid.NewGuid(),
                    FirebaseUid = $"uid-offboard-{Guid.NewGuid()}",
                    DisplayName = "Offboard",
                    Color = "#333333",
                });
            }
            await noise.SaveChangesAsync();
        }

        Guid newcomer;
        await using (var db = NewDb())
        {
            var registered = await new UserService(db, Mock.Of<IValidationService>(), NullLogger<UserService>.Instance)
                .Register(
                    new RegisterRequest { DisplayName = "New", Color = "#222222" },
                    $"uid-new-{Guid.NewGuid()}", "google");
            newcomer = registered.Id;
        }

        await using var check = NewDb();
        var entry = await check.LeaderboardEntries
            .SingleAsync(l => l.UserId == newcomer && l.Date == today);

        // Exactly two players have CellCount > 0, so the newcomer is 3rd — not 9th (the
        // total user count), and tied with the existing zero-cell player rather than behind it.
        Assert.Equal(3, entry.Rank);
        Assert.Equal(0, entry.CellCount);
    }

    [Fact]
    public async Task Signup_during_the_blank_window_does_not_hide_the_latest_snapshot()
    {
        // Yesterday's snapshot exists; today's refresh hasn't run. A new registration must
        // join the visible snapshot — a today-dated row would become the newest "snapshot"
        // and shrink the board to just that one zero-cell signup for every reader.
        var yesterday = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-1);
        var veteran = await SeedRankedUser(100, 1, yesterday);
        await SeedRankedUser(90, 2, yesterday);

        Guid newcomer;
        await using (var db = NewDb())
        {
            var registered = await new UserService(db, Mock.Of<IValidationService>(), NullLogger<UserService>.Instance).Register(
                new RegisterRequest { DisplayName = "New", Color = "#222222" },
                $"uid-new-{Guid.NewGuid()}", "google");
            newcomer = registered.Id;
        }

        await using var check = NewDb();
        var board = await NewService(check).GetLeaderboard(0, 0, veteran, "global");

        // The full snapshot is still served, with the newcomer appended to it.
        Assert.Equal(3, board.Top.Count);
        Assert.Contains(board.Top, e => e.UserId == veteran);
        Assert.Contains(board.Top, e => e.UserId == newcomer);
        Assert.Equal(1, board.MyRank!.Rank);
    }

    [Fact]
    public async Task Profile_rank_tile_survives_the_blank_window()
    {
        var yesterday = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-1);
        await SeedRankedUser(100, 1, yesterday);
        var me = await SeedRankedUser(90, 2, yesterday);

        await using var db = NewDb();
        var profile = await new UserService(db, Mock.Of<IValidationService>(), NullLogger<UserService>.Instance).GetRichProfile(me);

        Assert.NotNull(profile);
        Assert.Equal(2, profile!.CurrentRank);
        Assert.Equal(2, profile.TotalPlayers);
    }
}
