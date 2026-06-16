using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Entities;
using MyLoop.Api.Services;

namespace MyLoop.Api.Data.Seeding;

/// <summary>
/// Idempotent database seeding. Populates bootstrap users, their leaderboard, and bot territory
/// only when the database is empty, and keeps today's leaderboard current on every startup.
/// </summary>
public static class DatabaseSeeder
{
    /// <summary>Seeds bootstrap data when there are no users yet; otherwise a no-op.</summary>
    public static async Task SeedAsync(AppDbContext db, ILogger logger)
    {
        if (await db.Users.AnyAsync())
            return;

        var users = SeedUsers.Build();
        db.Users.AddRange(users);
        await db.SaveChangesAsync();

        AddLeaderboardEntries(db, users, DateOnly.FromDateTime(DateTime.UtcNow));
        await db.SaveChangesAsync();

        // Seed territory hexes for bot users so the map isn't empty on day one.
        TerritorySeedService.SeedBotTerritory(db, users.ToList());
        logger.LogInformation(
            "Seeded {UserCount} bootstrap users with leaderboard entries and bot territory", users.Length);
    }

    /// <summary>Generates today's leaderboard from current hex counts if it doesn't exist yet.</summary>
    public static void EnsureTodayLeaderboard(AppDbContext db)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        if (db.LeaderboardEntries.Any(l => l.Date == today))
            return;

        var ranked = db.Users
            .OrderByDescending(u => u.HexCount)
            .Where(u => u.HexCount > 0)
            .ToList();
        AddLeaderboardEntries(db, ranked, today);
        db.SaveChanges();
    }

    private static void AddLeaderboardEntries(AppDbContext db, IReadOnlyList<User> users, DateOnly date)
    {
        var sorted = users.OrderByDescending(u => u.HexCount).ToList();
        for (int i = 0; i < sorted.Count; i++)
            db.LeaderboardEntries.Add(BuildEntry(sorted[i], date, rank: i + 1));
    }

    private static LeaderboardEntry BuildEntry(User user, DateOnly date, int rank) => new()
    {
        Id = Guid.NewGuid(),
        UserId = user.Id,
        Date = date,
        CellCount = user.HexCount,
        AreaM2 = user.HexCount * GameConstants.CellAreaSquareMeters,
        Rank = rank,
    };
}
