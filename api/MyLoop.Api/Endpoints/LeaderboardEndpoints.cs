using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Services;

namespace MyLoop.Api.Endpoints;

/// Leaderboard — who owns the most territory in the city.
/// Updated once a day at midnight by a batch job.
public static class LeaderboardEndpoints
{
    public static void MapLeaderboardEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/leaderboard");

        // Get today's leaderboard for a specific area. 
        // Send the center of your map view (lat/lng) and we find the city-level zone.
        // Also returns the requesting user's rank if userId is provided.
        group.MapGet("/", async (double lat, double lng, Guid? userId, AppDbContext db) =>
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);

            // Get top 10
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
                    l.CellCount,
                    l.AreaM2
                })
                .ToListAsync();

            // If a userId was provided, also find their rank
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

        // Trigger leaderboard refresh. In production this runs as a scheduled job.
        // For now, we expose it as an endpoint so we can test it manually.
        group.MapPost("/refresh", async (AppDbContext db) =>
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);

            // Delete today's old snapshot (if re-running)
            await db.LeaderboardEntries.Where(l => l.Date == today).ExecuteDeleteAsync();

            // Count cells per user, ranked by most cells
            var rankings = await db.TerritoryCells
                .GroupBy(t => t.OwnerId)
                .Select(g => new { UserId = g.Key, CellCount = g.Count() })
                .OrderByDescending(x => x.CellCount)
                .ToListAsync();

            // Write leaderboard entries with ranks
            var entries = rankings.Select((r, index) => new LeaderboardEntry
            {
                Id = Guid.NewGuid(),
                UserId = r.UserId,
                Date = today,
                CellCount = r.CellCount,
                AreaM2 = H3Service.CalculateArea(r.CellCount),
                Rank = index + 1
            });

            db.LeaderboardEntries.AddRange(entries);
            await db.SaveChangesAsync();

            return Results.Ok(new { Message = "Leaderboard refreshed", PlayerCount = rankings.Count });
        });
    }
}
