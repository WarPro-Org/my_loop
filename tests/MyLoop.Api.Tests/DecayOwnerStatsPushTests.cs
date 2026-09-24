using Microsoft.EntityFrameworkCore;
using Moq;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// Review fix for #104: the decay reaper decremented an owner's HexCount but only broadcast
/// HexesReleased to the region, so the owner's own client kept showing the old count until its
/// next game-state fetch. After a release each affected owner now gets one UserStatsDelta with
/// their ABSOLUTE post-release stats — parity with the theft path's victim push.
/// </summary>
public class DecayOwnerStatsPushTests
{
    private readonly string _dbName = $"decay-owner-stats-{Guid.NewGuid()}";

    private AppDbContext NewDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseInMemoryDatabase(_dbName).Options);

    private async Task<Guid> SeedUser(int hexCount, int streak)
    {
        var id = Guid.NewGuid();
        await using var db = NewDb();
        db.Users.Add(new User
        {
            Id = id,
            FirebaseUid = $"uid-{id}",
            DisplayName = "D",
            Color = "#555555",
            HexCount = hexCount,
            TotalHexesCaptured = 9,
            TotalHexesStolen = 2,
            Streak = streak,
            IsStreakActive = true,
            DistanceKm = 4.5,
        });
        await db.SaveChangesAsync();
        return id;
    }

    private static DecayedCellRow Row(long cellId, Guid ownerId) =>
        new() { CellId = cellId, OwnerId = ownerId, ParentCellId = 7L };

    [Fact]
    public async Task Pushes_one_absolute_stats_delta_per_affected_owner()
    {
        var owner = await SeedUser(hexCount: 3, streak: 4);
        var other = await SeedUser(hexCount: 10, streak: 1);
        var untouched = await SeedUser(hexCount: 5, streak: 2);
        var notifier = new Mock<ITerritoryNotifier>();

        await using var db = NewDb();
        await DecayCleanupService.PushOwnerStatsAsync(
            db, notifier.Object,
            [Row(1L, owner), Row(2L, owner), Row(3L, other)],
            CancellationToken.None);

        // Two cells from the same owner collapse into ONE push carrying the stored
        // (already decremented) HexCount, not a relative -2.
        notifier.Verify(n => n.NotifyUserStatsAsync(owner,
            new UserStatsDelta(3, 9, 2, 4, true, 4.5)), Times.Once);
        notifier.Verify(n => n.NotifyUserStatsAsync(other,
            It.Is<UserStatsDelta>(d => d.HexCount == 10)), Times.Once);
        notifier.Verify(n => n.NotifyUserStatsAsync(untouched, It.IsAny<UserStatsDelta>()),
            Times.Never);
    }

    [Fact]
    public async Task Pushes_nothing_for_an_empty_release()
    {
        var notifier = new Mock<ITerritoryNotifier>();

        await using var db = NewDb();
        await DecayCleanupService.PushOwnerStatsAsync(
            db, notifier.Object, [], CancellationToken.None);

        notifier.Verify(n => n.NotifyUserStatsAsync(It.IsAny<Guid>(), It.IsAny<UserStatsDelta>()),
            Times.Never);
    }
}
