using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;

namespace MyLoop.Api.Services;

/// <summary>
/// Background service that runs periodically to release decayed territory cells.
/// Hexes not refreshed (owner didn't walk through) within DecayDays are released.
/// Runs every hour — lightweight query with batch processing.
/// </summary>
public class DecayCleanupService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<DecayCleanupService> _logger;
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    public DecayCleanupService(IServiceScopeFactory scopeFactory, ILogger<DecayCleanupService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CleanupDecayedCells(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Decay cleanup failed");
            }

            await Task.Delay(Interval, stoppingToken);
        }
    }

    private async Task CleanupDecayedCells(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Pure SQL: decrement owner hex counts and delete decayed cells in one shot.
        // No entity loading, no memory pressure, no N+1 user lookups.
        var decremented = await db.Database.ExecuteSqlRawAsync("""
            WITH decayed AS (
                SELECT "OwnerId", COUNT(*) as cnt
                FROM "TerritoryCells"
                WHERE "LastRefreshedAt" + ("DecayDays" || ' days')::interval < NOW()
                GROUP BY "OwnerId"
            )
            UPDATE "Users" u
            SET "HexCount" = GREATEST(0, u."HexCount" - d.cnt)
            FROM decayed d
            WHERE u."Id" = d."OwnerId"
            """, ct);

        var deleted = await db.Database.ExecuteSqlRawAsync("""
            DELETE FROM "TerritoryCells"
            WHERE "CellId" IN (
                SELECT "CellId" FROM "TerritoryCells"
                WHERE "LastRefreshedAt" + ("DecayDays" || ' days')::interval < NOW()
                LIMIT 1000
            )
            """, ct);

        if (deleted > 0)
        {
            _logger.LogInformation("Decay cleanup: released {Count} cells, updated {Owners} owners",
                deleted, decremented);
        }
    }
}
