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

        // GET /api/leaderboard?lat=...&lng=...&userId=...&scope=city|country|world
        // Get today's leaderboard for a specific scope.
        // scope: "city" (default), "country", or "world"
        // Returns top 20 players + the requesting user's rank if not in top 20.
        group.MapGet("/", async (double lat, double lng, Guid? userId, string? scope, AppDbContext db) =>
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            var leaderboardScope = scope?.ToLowerInvariant() ?? "city";
            const int maxEntries = 20;

            // Determine the requesting user's city/country for scoped filtering
            string? userCity = null;
            string? userCountry = null;
            if (userId.HasValue)
            {
                var requestingUser = await db.Users.FindAsync(userId.Value);
                if (requestingUser != null)
                {
                    userCity = requestingUser.City;
                    userCountry = requestingUser.Country;
                }
            }

            // Build scoped query: filter leaderboard entries based on scope
            var query = db.LeaderboardEntries
                .Include(l => l.User)
                .Where(l => l.Date == today);

            // Apply scope filter based on requesting user's location
            if (leaderboardScope == "city" && !string.IsNullOrEmpty(userCity))
            {
                query = query.Where(l => l.User!.City == userCity);
            }
            else if (leaderboardScope == "country" && !string.IsNullOrEmpty(userCountry))
            {
                query = query.Where(l => l.User!.Country == userCountry);
            }
            // "world" = no filter (show everyone)

            // Retrieve the top players by rank for today's snapshot
            var top = await query
                .OrderBy(l => l.Rank)
                .Take(maxEntries)
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

            // Re-rank within scope (position in filtered list)
            var scopedTop = top.Select((entry, index) => new
            {
                Rank = index + 1,
                entry.UserId,
                entry.UserName,
                entry.UserColor,
                entry.UserAvatar,
                entry.UserHexCount,
                entry.UserStreak,
                entry.UserDistanceKm,
                entry.CellCount,
                entry.AreaM2
            }).ToList();

            // If a userId was provided, find their scoped rank
            object? myRank = null;
            if (userId.HasValue)
            {
                // Check if user is already in scopedTop
                var userEntry = scopedTop.FirstOrDefault(e => e.UserId == userId.Value);
                if (userEntry != null)
                {
                    myRank = new { userEntry.Rank, userEntry.CellCount, userEntry.AreaM2 };
                }
                else
                {
                    // User not in top 20 for this scope — get their global entry and compute scoped position
                    var globalEntry = await db.LeaderboardEntries
                        .Where(l => l.Date == today && l.UserId == userId.Value)
                        .Select(l => new { l.CellCount, l.AreaM2 })
                        .FirstOrDefaultAsync();
                    if (globalEntry != null)
                    {
                        // Count how many users in this scope have more cells
                        var higherCount = await query
                            .CountAsync(l => l.CellCount > globalEntry.CellCount);
                        myRank = new { Rank = higherCount + 1, globalEntry.CellCount, globalEntry.AreaM2 };
                    }
                }
            }

            return Results.Ok(new { Top = scopedTop, MyRank = myRank, Scope = leaderboardScope });
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
