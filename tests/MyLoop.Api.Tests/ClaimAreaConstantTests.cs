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
/// Regression for issue #51: the batch-step claim path hardcoded a per-hex area of 4234 m²,
/// while every other surface (HexGridService.CalculateArea, leaderboard, profile stats,
/// seeding, loop claim) uses the authoritative <see cref="GameConstants.CellAreaSquareMeters"/>
/// (2,150 m²). That made the stored <see cref="Claim.AreaM2"/> disagree by ~2x with
/// recomputed-from-cell-count areas.
///
/// The original trail/step claim paths this test once covered were removed as dead,
/// unvalidated endpoints (#53); the only surviving claim path that constructs a Claim from a
/// raw cell count is <see cref="TerritoryService.ProcessBatchStepClaim"/>, so the regression
/// guard now drives that. It runs against a real PostgreSQL (Testcontainers, matching
/// ClaimConcurrencyTests) and asserts the persisted area derives from the shared constant —
/// and is explicitly NOT the old 4234-based value, so it fails on the pre-fix code.
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

    // Mirrors ClaimConcurrencyTests.NewService — same dependency graph the live claim paths
    // already exercise, with hex-grid lookups stubbed so the claim is deterministic. Each GPS
    // point maps to its own distinct, unowned hex so the batch claims one cell per point.
    private TerritoryService NewService(AppDbContext db)
    {
        var hex = new Mock<IHexGridService>();
        hex.Setup(h => h.GetCellAtPoint(It.IsAny<double>(), It.IsAny<double>()))
            .Returns((double lat, double lng) => new HexCell
            {
                CellId = (long)Math.Round(lat * 100_000),
                Boundary = [[lat, lng]],
            });
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
        // The response DTO dereferences the AwardXp result, so an unstubbed null would throw
        // before the assert.
        missions.Setup(m => m.AwardXp(It.IsAny<Guid>(), It.IsAny<int>(), It.IsAny<string>()))
            .ReturnsAsync(new XpGainResult { TotalXp = 0, Level = 1, LeveledUp = false });
        var achievements = new Mock<IAchievementService> { DefaultValue = DefaultValue.Empty };
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
    public async Task BatchStep_claim_stores_area_from_GameConstants_not_legacy_4234()
    {
        var userId = await SeedUser();

        // Three distinct GPS points → three distinct, unowned hexes → three new claims.
        var points = new List<BatchStepPoint>
        {
            new() { ClientId = "a", Lat = 12.900, Lng = 77.500, CapturedAt = DateTime.UtcNow },
            new() { ClientId = "b", Lat = 12.901, Lng = 77.501, CapturedAt = DateTime.UtcNow },
            new() { ClientId = "c", Lat = 12.902, Lng = 77.502, CapturedAt = DateTime.UtcNow },
        };
        const int expectedCells = 3;

        await using (var db = NewDb())
        {
            var response = await NewService(db).ProcessBatchStepClaim(userId, clientLocalDate: null, points);
            Assert.Equal(expectedCells, response.Results.Count(r => r.Claimed));
        }

        await using var check = NewDb();
        var claim = await check.Claims.SingleAsync(c => c.UserId == userId);

        Assert.Equal(expectedCells, claim.CellCount);
        Assert.Equal(expectedCells * GameConstants.CellAreaSquareMeters, claim.AreaM2);
        // Regression guard: pre-fix this stored expectedCells * 4234.
        Assert.NotEqual(expectedCells * WrongLegacyAreaPerCell, claim.AreaM2);
    }
}
