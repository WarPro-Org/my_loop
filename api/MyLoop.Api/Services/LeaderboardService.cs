using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// Leaderboard operations — querying and refreshing daily rankings.
/// </summary>
public class LeaderboardService : ILeaderboardService
{
    private readonly AppDbContext _db;
    private readonly IHexGridService _hexGrid;

    public LeaderboardService(AppDbContext db, IHexGridService hexGrid)
    {
        _db = db;
        _hexGrid = hexGrid;
    }

    public async Task<LeaderboardResponse> GetLeaderboard(double lat, double lng, Guid? userId, string scope)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var leaderboardScope = scope.ToLowerInvariant();

        // Get the requesting user's city/country for scoped filtering
        string? userCity = null;
        string? userCountry = null;
        if (userId.HasValue)
        {
            var requestingUser = await _db.Users.FindAsync(userId.Value);
            if (requestingUser != null)
            {
                userCity = requestingUser.City;
                userCountry = requestingUser.Country;
            }
        }

        // Build scoped query
        var query = _db.LeaderboardEntries
            .Include(l => l.User)
            .Where(l => l.Date == today);

        if (leaderboardScope == "city" && !string.IsNullOrEmpty(userCity))
        {
            query = query.Where(l => l.User!.City == userCity);
        }
        else if (leaderboardScope == "country" && !string.IsNullOrEmpty(userCountry))
        {
            query = query.Where(l => l.User!.Country == userCountry);
        }

        // Get the top players
        var topEntries = await query
            .OrderBy(l => l.Rank)
            .Take(GameConstants.LeaderboardTopCount)
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

        // Re-rank within the scope (1-based position in filtered list)
        var scopedTop = new List<LeaderboardEntryResponse>();
        for (int i = 0; i < topEntries.Count; i++)
        {
            var entry = topEntries[i];
            scopedTop.Add(new LeaderboardEntryResponse
            {
                Rank = i + 1,
                UserId = entry.UserId,
                UserName = entry.UserName,
                UserColor = entry.UserColor,
                UserAvatar = entry.UserAvatar,
                UserHexCount = entry.UserHexCount,
                UserStreak = entry.UserStreak,
                UserDistanceKm = entry.UserDistanceKm,
                CellCount = entry.CellCount,
                AreaM2 = entry.AreaM2,
            });
        }

        // Find the requesting user's rank if not in the top list
        MyRankResponse? myRank = null;
        if (userId.HasValue)
        {
            var userInTop = scopedTop.FirstOrDefault(e => e.UserId == userId.Value);
            if (userInTop != null)
            {
                myRank = new MyRankResponse
                {
                    Rank = userInTop.Rank,
                    CellCount = userInTop.CellCount,
                    AreaM2 = userInTop.AreaM2,
                };
            }
            else
            {
                // User not in top list — compute their scoped rank
                var globalEntry = await _db.LeaderboardEntries
                    .Where(l => l.Date == today && l.UserId == userId.Value)
                    .Select(l => new { l.CellCount, l.AreaM2 })
                    .FirstOrDefaultAsync();

                if (globalEntry != null)
                {
                    var higherCount = await query
                        .CountAsync(l => l.CellCount > globalEntry.CellCount);

                    myRank = new MyRankResponse
                    {
                        Rank = higherCount + 1,
                        CellCount = globalEntry.CellCount,
                        AreaM2 = globalEntry.AreaM2,
                    };
                }
            }
        }

        return new LeaderboardResponse
        {
            Top = scopedTop,
            MyRank = myRank,
            Scope = leaderboardScope,
        };
    }

    public async Task<int> RefreshLeaderboard()
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        await using var transaction = await _db.Database.BeginTransactionAsync();

        // Delete today's old snapshot
        await _db.LeaderboardEntries.Where(l => l.Date == today).ExecuteDeleteAsync();

        // Aggregate: count cells per user, ordered by most territory
        var rankings = await _db.TerritoryCells
            .GroupBy(t => t.OwnerId)
            .Select(g => new { UserId = g.Key, CellCount = g.Count() })
            .OrderByDescending(x => x.CellCount)
            .ToListAsync();

        // Create ranked entries
        var entries = new List<LeaderboardEntry>();
        for (int i = 0; i < rankings.Count; i++)
        {
            entries.Add(new LeaderboardEntry
            {
                Id = Guid.NewGuid(),
                UserId = rankings[i].UserId,
                Date = today,
                CellCount = rankings[i].CellCount,
                AreaM2 = _hexGrid.CalculateArea(rankings[i].CellCount),
                Rank = i + 1,
            });
        }

        _db.LeaderboardEntries.AddRange(entries);
        await _db.SaveChangesAsync();

        // Increment achievement counters for ranked users
        foreach (var entry in entries)
        {
            var user = await _db.Users.FindAsync(entry.UserId);
            if (user == null) continue;

            if (entry.Rank <= 3) user.TopThreeFinishes++;
            if (entry.Rank <= 10) user.TopTenFinishes++;
            if (entry.Rank <= 100) user.TopHundredFinishes++;
            if (entry.Rank <= 1000) user.TopThousandFinishes++;
        }

        // Purge leaderboard entries older than 7 days
        var cutoff = today.AddDays(-GameConstants.LeaderboardRetentionDays);
        await _db.LeaderboardEntries.Where(l => l.Date < cutoff).ExecuteDeleteAsync();

        await _db.SaveChangesAsync();
        await transaction.CommitAsync();

        return rankings.Count;
    }
}
