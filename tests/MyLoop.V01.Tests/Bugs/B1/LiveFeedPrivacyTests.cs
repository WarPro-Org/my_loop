using System.Reflection;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Hubs;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Services;

namespace MyLoop.V01.Tests.Bugs.B1;

/// <summary>
/// Bug B1 (PRIV-2): the live map feed needs sign-in, and every update reaches only the player
/// it is about — never a region group, and never another player's name.
/// </summary>
public class LiveFeedPrivacyTests
{
    private static readonly Guid Taker = Guid.NewGuid();
    private static readonly Guid Loser = Guid.NewGuid();
    private const string TakerName = "Taker Name";
    private const long Region = 599686042433355775L;

    /// <summary>Every (group, method, payload JSON) the notifier sends.</summary>
    private sealed class SentMessages
    {
        public List<(string Group, string Method, string Json)> All { get; } = [];
    }

    private static (TerritoryNotifier Notifier, SentMessages Sent) Notifier()
    {
        var sent = new SentMessages();
        var clients = new Mock<IHubClients>();
        clients.Setup(c => c.Group(It.IsAny<string>())).Returns((string group) =>
        {
            var proxy = new Mock<IClientProxy>();
            proxy.Setup(p => p.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
                .Callback((string method, object?[] args, CancellationToken _) =>
                    sent.All.Add((group, method, JsonSerializer.Serialize(args))))
                .Returns(Task.CompletedTask);
            return proxy.Object;
        });
        var hub = new Mock<IHubContext<TerritoryHub>>();
        hub.Setup(h => h.Clients).Returns(clients.Object);
        return (new TerritoryNotifier(hub.Object, NullLogger<TerritoryNotifier>.Instance), sent);
    }

    private static HexChangeEvent TakenFromLoser(string h3) =>
        new(h3, 12.9, 77.5, Taker, "#123456", TakerName, Loser, Region);

    [Fact]
    public void Hub_requires_sign_in()
    {
        Assert.NotNull(typeof(TerritoryHub).GetCustomAttribute<AuthorizeAttribute>());
    }

    [Fact]
    public async Task Ownership_change_reaches_only_the_players_it_is_about()
    {
        var (notifier, sent) = Notifier();

        await notifier.NotifyHexOwnershipChanged([TakenFromLoser("8b1"), TakenFromLoser("8b2")]);

        Assert.Equal(new HashSet<string> { $"user_{Taker}", $"user_{Loser}" }, sent.All.Select(m => m.Group).ToHashSet());
        Assert.DoesNotContain(sent.All, m => m.Group == Region.ToString());
        var taker = Assert.Single(sent.All, m => m.Group == $"user_{Taker}");
        Assert.Equal("HexOwnershipChanged", taker.Method);
    }

    [Fact]
    public async Task Player_who_lost_a_hex_learns_it_left_their_map_but_not_who_took_it()
    {
        var (notifier, sent) = Notifier();

        await notifier.NotifyHexOwnershipChanged([TakenFromLoser("8b1")]);

        var loser = Assert.Single(sent.All, m => m.Group == $"user_{Loser}");
        Assert.Equal("HexesReleased", loser.Method);
        Assert.Contains("8b1", loser.Json);
        Assert.DoesNotContain(TakerName, loser.Json);
        Assert.DoesNotContain(Taker.ToString(), loser.Json);
    }

    [Fact]
    public async Task Decay_release_reaches_only_the_former_owner()
    {
        var (notifier, sent) = Notifier();
        var other = Guid.NewGuid();

        await notifier.NotifyHexesReleasedAsync(
            [new HexReleasedEvent("8b1", Region, Loser), new HexReleasedEvent("8b2", Region, other)]);

        Assert.Equal(2, sent.All.Count);
        Assert.Contains("8b1", Assert.Single(sent.All, m => m.Group == $"user_{Loser}").Json);
        Assert.Contains("8b2", Assert.Single(sent.All, m => m.Group == $"user_{other}").Json);
        Assert.DoesNotContain(sent.All, m => m.Group == Region.ToString());
    }

    [Fact]
    public async Task JoinRegion_from_an_old_app_joins_nothing_and_does_not_fail()
    {
        var hexGrid = new Mock<IHexGridService>();
        hexGrid.Setup(h => h.IsValidRegionId(It.IsAny<string>())).Returns(true);
        var groups = new Mock<IGroupManager>(MockBehavior.Strict);
        var hub = new TerritoryHub(Mock.Of<IUserService>(), hexGrid.Object, NullLogger<TerritoryHub>.Instance)
        {
            Groups = groups.Object,
        };

        await hub.JoinRegion(Region.ToString());

        groups.VerifyNoOtherCalls();
    }
}
