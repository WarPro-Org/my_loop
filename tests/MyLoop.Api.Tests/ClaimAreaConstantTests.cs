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
/// Regression for issue #51: the step / trail / batch-step claim paths hardcoded a
/// per-hex area of 4234 m², while every other surface (HexGridService.CalculateArea,
/// leaderboard, profile stats, seeding, loop claim) uses the authoritative
/// <see cref="GameConstants.CellAreaSquareMeters"/> (2,150 m²). That made stored
/// <see cref="Claim.AreaM2"/> disagree by ~2x with recomputed-from-cell-count areas.
///
/// These tests drive the real claim paths against a real PostgreSQL (Testcontainers,
/// matching ClaimConcurrencyTests) and assert the persisted area derives from the shared
/// constant — and is explicitly NOT the old 4234-based value, so the tests fail on the
/// pre-fix code.
/// </summary>
public class ClaimAreaConstantTests : IAsyncLifetime
{
    private const double WrongLegacyAreaPerCell = 4234.0;

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

    private static HexCell Cell(long id) => new() { CellId = id, Boundary = [[12.9, 77.5]] };

    // Mirrors ClaimConcurrencyTests.NewService — same dependency graph the loop claim
    // already exercises, with the hex-grid lookups stubbed so the claim is deterministic.
    private TerritoryService NewService(AppDbContext db, IReadOnlyList<HexCell> trailCells, HexCell stepCell)
    {
        var hex = new Mock<IHexGridService>();
        hex.Setup(h => h.GetTrailCells(It.IsAny<double[][]>())).Returns(trailCells.ToList());
        hex.Setup(h => h.GetCellAtPoint(It.IsAny<double>(), It.IsAny<double>())).Returns(stepCell);
        hex.Setup(h => h.CalculateArea(It.IsAny<int>())).Returns(100.0);
        hex.Setup(h => h.GetCellCenter(It.IsAny<long>())).Returns(new GeoCoordinate { Lat = 12.9, Lng = 77.5 });
        hex.Setup(h => h.GetParentCellId(It.IsAny<long>())).Returns(1L);
        hex.Setup(h => h.GetNeighborhoodId(It.IsAny<long>())).Returns(2L);

        var geo = new Mock<IGeoService>();
        geo.Setup(g => g.CalculatePathDistance(It.IsAny<double[][]>())).Returns(250.0);

        var pathValidator = new Mock<IPathValidationService>(); // Validate() -> null (allowed)

        var notifier = new Mock<ITerritoryNotifier> { DefaultValue = DefaultValue.Empty };
        var push = new Mock<IPushNotificationService> { DefaultValue = DefaultValue.Empty };
        var missions = new Mock<IMissionService> { DefaultValue = DefaultValue.Empty };
        // ProcessStepClaim dereferences the AwardXp result for the response DTO
        // (LeveledUp/NewLevel), so an unstubbed null would throw before the assert.
        missions.Setup(m => m.AwardXp(It.IsAny<Guid>(), It.IsAny<int>(), It.IsAny<string>()))
            .ReturnsAsync(new XpGainResult { TotalXp = 0, Level = 1, LeveledUp = false });
        var achievements = new Mock<IAchievementService> { DefaultValue = DefaultValue.Empty };
        // ProcessStepClaim derefs the CheckAndUnlock result in its response DTO; the
        // DefaultValue.Empty mock returns null for Task<List<T>>, so stub an empty list.
        achievements.Setup(a => a.CheckAndUnlock(It.IsAny<Guid>()))
            .ReturnsAsync(new List<AchievementUnlock>());

        return new TerritoryService(
            db, hex.Object, geo.Object, notifier.Object, pathValidator.Object,
            push.Object, new GeocodingService(new HttpClient(), NullLogger<GeocodingService>.Instance),
            missions.Object, achievements.Object, NullLogger<TerritoryService>.Instance);
    }

    private async Task<Guid> SeedUser()
    {
        var userId = Guid.NewGuid();
        await using var seed = NewDb();
        // No home location set → decay calc uses the default (no geocoding HTTP call).
        seed.Users.Add(new User { Id = userId, FirebaseUid = "uid", DisplayName = "Player", Color = "#111111" });
        await seed.SaveChangesAsync();
        return userId;
    }

    [Fact]
    public async Task Trail_claim_stores_area_from_GameConstants_not_legacy_4234()
    {
        var userId = await SeedUser();
        var cells = new[] { Cell(1001L), Cell(1002L), Cell(1003L) };

        double[][] points = [[12.900, 77.500], [12.901, 77.501], [12.902, 77.502]];

        await using (var db = NewDb())
        {
            var result = await NewService(db, cells, Cell(1001L)).ProcessTrailClaim(userId, points);
            Assert.True(result.Success);
        }

        await using var check = NewDb();
        var claim = await check.Claims.SingleAsync(c => c.UserId == userId);

        Assert.Equal(cells.Length, claim.CellCount);
        Assert.Equal(cells.Length * GameConstants.CellAreaSquareMeters, claim.AreaM2);
        // Regression guard: pre-fix this stored cells.Count * 4234.
        Assert.NotEqual(cells.Length * WrongLegacyAreaPerCell, claim.AreaM2);
    }

    [Fact]
    public async Task Step_claim_stores_single_cell_area_from_GameConstants_not_legacy_4234()
    {
        var userId = await SeedUser();
        var stepCell = Cell(2001L);

        await using (var db = NewDb())
        {
            var response = await NewService(db, [], stepCell).ProcessStepClaim(userId, 12.9, 77.5);
            Assert.True(response.Claimed);
        }

        await using var check = NewDb();
        var claim = await check.Claims.SingleAsync(c => c.UserId == userId);

        Assert.Equal(1, claim.CellCount);
        Assert.Equal(GameConstants.CellAreaSquareMeters, claim.AreaM2);
        // Regression guard: pre-fix this stored 4234.
        Assert.NotEqual(WrongLegacyAreaPerCell, claim.AreaM2);
    }
}
