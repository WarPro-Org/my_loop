using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using MyLoop.Api.Controllers;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;
using MyLoop.Api.Models;
using MyLoop.Api.Services;

namespace MyLoop.V01.Tests.Bugs.B1;

/// <summary>
/// Bug B1 (PRIV-1): in single-player 0.1 a signed-in player reads only their own land, account,
/// profile and rank. Another player's id is refused, and lists never contain other players.
/// </summary>
public class ReadPrivacyTests
{
    private static readonly Guid Me = Guid.NewGuid();
    private static readonly Guid Other = Guid.NewGuid();

    private static AppDbContext NewDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static ICurrentUser SignedInAs(Guid id) =>
        Mock.Of<ICurrentUser>(u => u.TryGetUserIdAsync() == Task.FromResult<Guid?>(id));

    private static T WithHttp<T>(T controller) where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() };
        return controller;
    }

    private static async Task SeedTwoPlayers(AppDbContext db)
    {
        foreach (var (id, name) in new[] { (Me, "Me"), (Other, "Other") })
        {
            db.Users.Add(new User { Id = id, FirebaseUid = $"uid-{id}", DisplayName = name, Color = "#111111" });
            db.LeaderboardEntries.Add(new LeaderboardEntry
            {
                Id = Guid.NewGuid(), UserId = id, Date = DateOnly.FromDateTime(DateTime.UtcNow),
                CellCount = id == Me ? 1 : 5, Rank = id == Me ? 2 : 1,
            });
        }
        db.TerritoryCells.Add(Cell(1001, Me));
        db.TerritoryCells.Add(Cell(1002, Other));
        await db.SaveChangesAsync();
    }

    private static TerritoryCell Cell(long cellId, Guid ownerId)
    {
        var cell = new TerritoryCell
        {
            CellId = cellId, OwnerId = ownerId, ClaimId = Guid.NewGuid(), ClaimedAt = DateTime.UtcNow,
            LastRefreshedAt = DateTime.UtcNow, CenterLat = 12.9, CenterLng = 77.5, ParentCellId = 1, DecayDays = 7,
        };
        cell.SetBoundary([[12.9, 77.5]]);
        return cell;
    }

    /// <summary>An empty region set means "too wide to prune": the coordinate filter alone decides.</summary>
    private static IHexGridService NoRegionPruning()
    {
        var hex = new Mock<IHexGridService>();
        hex.Setup(h => h.GetRegionIdsForBbox(It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>(), It.IsAny<double>()))
            .Returns([]);
        return hex.Object;
    }

    private static TerritoryService Territory(AppDbContext db) =>
        new(db, NoRegionPruning(), Mock.Of<IGeoService>(), Mock.Of<ITerritoryNotifier>(),
            Mock.Of<IPathValidationService>(), Mock.Of<IPushNotificationService>(),
            new GeocodingService(new HttpClient(), NullLogger<GeocodingService>.Instance),
            Mock.Of<IMissionService>(), Mock.Of<IAchievementService>(), Mock.Of<IServiceScopeFactory>(),
            NullLogger<TerritoryService>.Instance);

    private static UsersController Users(IUserService users) =>
        WithHttp(new UsersController(users, Mock.Of<IValidationService>(), Mock.Of<IPushNotificationService>(),
            new GeocodingService(new HttpClient(), NullLogger<GeocodingService>.Instance), NewDb(), SignedInAs(Me),
            Mock.Of<IMissionService>(), Mock.Of<IAchievementService>(), Mock.Of<ITerritoryService>(),
            NullLogger<UsersController>.Instance));

    [Fact]
    public async Task Map_area_returns_only_the_callers_hexes()
    {
        await using var db = NewDb();
        await SeedTwoPlayers(db);

        var result = await Territory(db).GetTerritoriesInViewport(Me, 12.0, 77.0, 13.0, 78.0);

        Assert.Equal(new long[] { 1001 }, result.Cells.Select(c => c.CellId));
    }

    [Fact]
    public async Task Map_area_request_is_answered_for_the_signed_in_caller()
    {
        var territory = new Mock<ITerritoryService>();
        territory.Setup(t => t.GetTerritoriesInViewport(It.IsAny<Guid>(), It.IsAny<double>(), It.IsAny<double>(),
                It.IsAny<double>(), It.IsAny<double>()))
            .ReturnsAsync(new TerritoryViewportResult());
        var controller = WithHttp(new TerritoryController(territory.Object, SignedInAs(Me),
            NullLogger<TerritoryController>.Instance));

        await controller.GetTerritoriesInViewport(12.0, 77.0, 13.0, 78.0);

        territory.Verify(t => t.GetTerritoriesInViewport(Me, 12.0, 77.0, 13.0, 78.0), Times.Once);
    }

    [Fact]
    public async Task Map_area_checks_the_caller_before_any_request_value()
    {
        var territory = new Mock<ITerritoryService>();
        var signedOut = Mock.Of<ICurrentUser>(u => u.TryGetUserIdAsync() == Task.FromResult<Guid?>(null));
        var controller = WithHttp(new TerritoryController(territory.Object, signedOut,
            NullLogger<TerritoryController>.Instance));

        // An invalid box must not decide whether the caller check runs (CodeQL).
        Assert.IsType<UnauthorizedResult>(await controller.GetTerritoriesInViewport(double.NaN, 77.0, 13.0, 78.0));
        territory.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task Another_players_hexes_are_refused_and_the_callers_own_are_served()
    {
        var territory = new Mock<ITerritoryService> { DefaultValue = DefaultValue.Empty };
        var controller = WithHttp(new TerritoryController(territory.Object, SignedInAs(Me),
            NullLogger<TerritoryController>.Instance));

        Assert.IsType<ForbidResult>(await controller.GetUserTerritories(Other));
        Assert.IsType<OkObjectResult>(await controller.GetUserTerritories(Me));
    }

    [Fact]
    public async Task Another_players_account_and_profile_are_refused_and_the_callers_own_are_served()
    {
        var users = new Mock<IUserService>();
        users.Setup(u => u.GetById(Me)).ReturnsAsync(
            new User { Id = Me, FirebaseUid = "uid-me", DisplayName = "Me", Color = "#111111" });
        users.Setup(u => u.GetRichProfile(Me)).ReturnsAsync(new UserProfileResponse());
        var controller = Users(users.Object);

        Assert.IsType<ForbidResult>(await controller.GetById(Other));
        Assert.IsType<ForbidResult>(await controller.GetProfile(Other));
        Assert.IsType<OkObjectResult>(await controller.GetById(Me));
        Assert.IsType<OkObjectResult>(await controller.GetProfile(Me));
    }

    [Fact]
    public async Task Leaderboard_contains_no_other_player()
    {
        await using var db = NewDb();
        await SeedTwoPlayers(db);

        var board = await new LeaderboardService(db, Mock.Of<IHexGridService>()).GetLeaderboard(12.9, 77.5, Me, "world");

        Assert.Equal(new[] { Me }, board.Top.Select(e => e.UserId));
    }

    [Fact]
    public async Task Stolen_hex_push_names_no_one()
    {
        await using var db = NewDb();
        db.DeviceTokens.Add(new DeviceToken { UserId = Me, Token = "token-me" });
        await db.SaveChangesAsync();
        var bodies = new List<string>();
        var fcm = new Mock<IFcmSender>();
        fcm.Setup(f => f.SendEachAsync(It.IsAny<IReadOnlyList<string>>(), It.IsAny<string>(), It.IsAny<string>()))
            .Callback((IReadOnlyList<string> _, string _, string body) => bodies.Add(body))
            .ReturnsAsync([]);

        await new PushNotificationService(db, fcm.Object, NullLogger<PushNotificationService>.Instance)
            .NotifyHexStolen(Me);

        Assert.Equal(["Some of your hexes were captured."], bodies);
    }

    [Fact]
    public void A_claimed_step_that_took_a_hex_does_not_name_the_player_who_lost_it()
    {
        var result = TerritoryService.ClaimedStepResult("c1", 1001, new HexCell { Boundary = [[12.9, 77.5]] }, wasStolen: true);

        Assert.True(result.WasStolen);
        Assert.Null(result.PreviousOwnerName);
    }

    [Fact]
    public async Task Lost_hexes_list_says_nothing_about_who_took_them()
    {
        await using var db = NewDb();
        var takerClaim = Guid.NewGuid();
        db.CellTransfers.Add(new CellTransfer
        {
            Id = Guid.NewGuid(), CellId = 1001, FromUserId = Me, ToUserId = Other, ClaimId = takerClaim,
            TransferredAt = DateTime.UtcNow, Reason = TransferReason.Capture,
        });
        await db.SaveChangesAsync();

        var lost = await Territory(db).GetStolenCells(Me, days: 7);

        Assert.Equal(1, lost.TotalStolen);
        var json = System.Text.Json.JsonSerializer.Serialize(lost);
        Assert.DoesNotContain(Other.ToString(), json);
        Assert.DoesNotContain(takerClaim.ToString(), json);
    }
}
