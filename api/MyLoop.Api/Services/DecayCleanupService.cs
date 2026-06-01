using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
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

        var cutoff = DateTime.UtcNow.AddDays(-GameConstants.DecayDays);

        // Find all cells whose owner hasn't refreshed within the decay window
        var decayedCells = await db.TerritoryCells
            .Where(t => t.LastRefreshedAt < cutoff)
            .Take(1000) // Process in batches to avoid long transactions
            .ToListAsync(ct);

        if (decayedCells.Count == 0) return;

        // Group by owner to decrement hex counts efficiently
        var ownerGroups = decayedCells.GroupBy(c => c.OwnerId).ToList();

        foreach (var group in ownerGroups)
        {
            var user = await db.Users.FindAsync([group.Key], ct);
            if (user != null)
            {
                user.HexCount = Math.Max(0, user.HexCount - group.Count());
            }
        }

        // Remove the decayed cells from the territory map
        db.TerritoryCells.RemoveRange(decayedCells);
        await db.SaveChangesAsync(ct);

        _logger.LogInformation("Decay cleanup: released {Count} cells from {Owners} owners",
            decayedCells.Count, ownerGroups.Count);
    }
}
