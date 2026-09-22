using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;
using MyLoop.Api.Services.Moderation;
using Testcontainers.PostgreSql;
using Xunit;

namespace MyLoop.Api.Tests;

/// <summary>
/// DR-002b / #190 — blocking (App Store Guideline 1.2): the block list itself, and that a blocked
/// player's name never reaches the blocker's push notifications.
/// </summary>
public class BlockFlowTests : IAsyncLifetime
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

    private async Task<List<Guid>> SeedUsers(int count, string tokenPrefix = "")
    {
        var ids = Enumerable.Range(0, count).Select(_ => Guid.NewGuid()).ToList();
        await using var db = NewDb();
        foreach (var id in ids)
        {
            db.Users.Add(new User { Id = id, FirebaseUid = $"uid-{id}", DisplayName = "Player", Color = "#00D4AA" });
            if (tokenPrefix != "")
                db.DeviceTokens.Add(new DeviceToken { Id = Guid.NewGuid(), UserId = id, Token = $"{tokenPrefix}-{id}" });
        }
        await db.SaveChangesAsync();
        return ids;
    }

    private sealed class RecordingFcmSender : IFcmSender
    {
        public List<string> Bodies { get; } = [];
        public Task<IReadOnlyList<FcmSendOutcome>> SendEachAsync(IReadOnlyList<string> tokens, string title, string body)
        {
            Bodies.Add(body);
            IReadOnlyList<FcmSendOutcome> outcomes = tokens.Select(t => new FcmSendOutcome(t, true, false)).ToList();
            return Task.FromResult(outcomes);
        }
    }

    [Fact]
    public async Task Block_is_idempotent_listed_and_reversible()
    {
        var users = await SeedUsers(2);
        await using var db = NewDb();
        var blocks = new BlockService(db);

        Assert.Equal(BlockOutcome.Done, await blocks.BlockAsync(users[0], users[1]));
        Assert.Equal(BlockOutcome.Done, await blocks.BlockAsync(users[0], users[1]));
        Assert.Equal([users[1]], await blocks.ListBlockedAsync(users[0]));
        Assert.Empty(await blocks.ListBlockedAsync(users[1])); // one-directional

        await blocks.UnblockAsync(users[0], users[1]);
        await blocks.UnblockAsync(users[0], users[1]); // idempotent
        Assert.Empty(await blocks.ListBlockedAsync(users[0]));
    }

    [Fact]
    public async Task Self_unknown_and_over_limit_blocks_are_refused()
    {
        var users = await SeedUsers(GameConstants.MaxBlocksPerUser + 2);
        var blocker = users[0];
        await using var db = NewDb();
        var blocks = new BlockService(db);

        Assert.Equal(BlockOutcome.SelfBlock, await blocks.BlockAsync(blocker, blocker));
        Assert.Equal(BlockOutcome.NotFound, await blocks.BlockAsync(blocker, Guid.NewGuid()));

        foreach (var target in users.Skip(1).Take(GameConstants.MaxBlocksPerUser))
            Assert.Equal(BlockOutcome.Done, await blocks.BlockAsync(blocker, target));
        Assert.Equal(BlockOutcome.LimitReached, await blocks.BlockAsync(blocker, users[^1]));
    }

    [Fact]
    public async Task A_blocked_thief_is_anonymous_in_the_victims_push_only()
    {
        var users = await SeedUsers(3, tokenPrefix: "token");
        var (victim, blockedThief, otherThief) = (users[0], users[1], users[2]);
        await using (var db = NewDb())
            await new BlockService(db).BlockAsync(victim, blockedThief);

        var sender = new RecordingFcmSender();
        await using (var db = NewDb())
        {
            var push = new PushNotificationService(db, sender, NullLogger<PushNotificationService>.Instance);
            await push.NotifyHexStolen(victim, blockedThief, "Rude Name", 2);
            await push.NotifyHexStolen(victim, otherThief, "Kai", 1);
        }

        Assert.Equal("A player captured 2 of your hexes!", sender.Bodies[0]);
        Assert.DoesNotContain("Rude Name", sender.Bodies[0]);
        Assert.Equal("Kai captured one of your hexes!", sender.Bodies[1]);
    }

    [Fact]
    public async Task Deleting_either_account_removes_the_block()
    {
        var users = await SeedUsers(2);
        await using (var db = NewDb())
            await new BlockService(db).BlockAsync(users[0], users[1]);

        await using (var db = NewDb())
            Assert.True(await new UserService(db, new ValidationService(), NullLogger<UserService>.Instance).DeleteAccount(users[1]));

        await using var check = NewDb();
        Assert.False(await check.UserBlocks.AnyAsync());
    }
}
