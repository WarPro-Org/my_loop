using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Services;

namespace MyLoop.Api.Endpoints;

/// <summary>
/// Leaderboard endpoints — displays ranked territory ownership for the current day.
/// The leaderboard is a daily snapshot computed by a batch refresh (triggered manually or by scheduled job).
/// </summary>
public static class LeaderboardEndpoints
{
    /// <summary>
    /// Maps all leaderboard-related HTTP endpoints under the <c>/api/leaderboard</c> route group.
    /// </summary>
    /// <param name="app">The <see cref="WebApplication"/> to register routes on.</param>
    public static void MapLeaderboardEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/leaderboard");

        // GET /api/leaderboard?lat=...&lng=...&userId=...
        // Get today's leaderboard for a specific area.
        // Send the center of your map view (lat/lng) and we find the city-level zone.
        // Also returns the requesting user's rank if userId is provided.
        group.MapGet("/", async (double lat, double lng, Guid? userId, AppDbContext db) =>
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);

            // Retrieve the top 10 players by rank for today's snapshot
            var top = await db.LeaderboardEntries
                .Include(l => l.User)
                .Where(l => l.Date == today)
                .OrderBy(l => l.Rank)
                .Take(10)
                .Select(l => new
                {
                    l.Rank,
                    l.UserId,
                    UserName = l.User!.DisplayName,
                    UserColor = l.User!.Color,
                    UserAvatar = l.User!.AvatarId,
                    UserHexCount = l.User!.HexCount,
                    UserStreak = l.User!.Streak,
                    UserDistanceKm = l.User!.DistanceKm,
                    l.CellCount,
                    l.AreaM2
                })
                .ToListAsync();

            // If a userId was provided, also find their personal rank
            // (they may not be in the top 10 but still want to see their position)
            object? myRank = null;
            if (userId.HasValue)
            {
                myRank = await db.LeaderboardEntries
                    .Where(l => l.Date == today && l.UserId == userId.Value)
                    .Select(l => new { l.Rank, l.CellCount, l.AreaM2 })
                    .FirstOrDefaultAsync();
            }

            return Results.Ok(new { Top = top, MyRank = myRank });
        });

        // POST /api/leaderboard/refresh
        // Trigger leaderboard refresh. In production this would be a scheduled CRON job.
        // For now, exposed as an endpoint for manual testing and development.
        group.MapPost("/refresh", async (AppDbContext db) =>
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);

            // Use a transaction to prevent readers seeing empty leaderboard mid-refresh
            await using var transaction = await db.Database.BeginTransactionAsync();

            // Delete today's old snapshot (allows safe re-running without duplicates)
            await db.LeaderboardEntries.Where(l => l.Date == today).ExecuteDeleteAsync();

            // Aggregate: count cells per user, ordered by most territory owned
            var rankings = await db.TerritoryCells
                .GroupBy(t => t.OwnerId)
                .Select(g => new { UserId = g.Key, CellCount = g.Count() })
                .OrderByDescending(x => x.CellCount)
                .ToListAsync();

            // Materialize ranked entries with 1-based rank positions
            var entries = rankings.Select((r, index) => new LeaderboardEntry
            {
                Id = Guid.NewGuid(),
                UserId = r.UserId,
                Date = today,
                CellCount = r.CellCount,
                AreaM2 = H3Service.CalculateArea(r.CellCount),
                Rank = index + 1 // rank is 1-based (1st place, 2nd place, etc.)
            });

            db.LeaderboardEntries.AddRange(entries);
            await db.SaveChangesAsync();
            await transaction.CommitAsync();

            return Results.Ok(new { Message = "Leaderboard refreshed", PlayerCount = rankings.Count });
        });
    }
}
