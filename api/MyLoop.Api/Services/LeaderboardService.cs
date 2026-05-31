using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

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

        var query = BuildScopedQuery(today, leaderboardScope, userId);
        var scopedTop = await FetchTopEntries(query);
        var myRank = await ResolveUserRank(userId, scopedTop, query, today);

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

        await _db.LeaderboardEntries.Where(l => l.Date == today).ExecuteDeleteAsync();

        var rankings = await _db.TerritoryCells
            .GroupBy(t => t.OwnerId)
            .Select(g => new { UserId = g.Key, CellCount = g.Count() })
            .OrderByDescending(x => x.CellCount)
            .ToListAsync();

        var entries = rankings.Select((r, i) => new LeaderboardEntry
        {
            Id = Guid.NewGuid(),
            UserId = r.UserId,
            Date = today,
            CellCount = r.CellCount,
            AreaM2 = _hexGrid.CalculateArea(r.CellCount),
            Rank = i + 1,
        }).ToList();

        _db.LeaderboardEntries.AddRange(entries);
        await _db.SaveChangesAsync();

        await UpdateAchievementCounters(entries);
        await PurgeOldEntries(today);

        await _db.SaveChangesAsync();
        await transaction.CommitAsync();

        return rankings.Count;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ──────────────────────────────────────────────────────────────────────────

    private IQueryable<LeaderboardEntry> BuildScopedQuery(DateOnly today, string scope, Guid? userId)
    {
        var query = _db.LeaderboardEntries
            .Include(l => l.User)
            .Where(l => l.Date == today);

        if (scope is not ("city" or "country")) return query;
        if (!userId.HasValue) return query;

        var user = _db.Users.Find(userId.Value);
        if (user == null) return query;

        return scope switch
        {
            "city" when !string.IsNullOrEmpty(user.City) => query.Where(l => l.User!.City == user.City),
            "country" when !string.IsNullOrEmpty(user.Country) => query.Where(l => l.User!.Country == user.Country),
            _ => query,
        };
    }

    private static async Task<List<LeaderboardEntryResponse>> FetchTopEntries(IQueryable<LeaderboardEntry> query)
    {
        var topEntries = await query
            .OrderBy(l => l.Rank)
            .Take(GameConstants.LeaderboardTopCount)
            .Select(l => new
            {
                l.UserId,
                UserName = l.User!.DisplayName,
                UserColor = l.User!.Color,
                UserAvatar = l.User!.AvatarId,
                UserHexCount = l.User!.HexCount,
                UserStreak = l.User!.Streak,
                UserDistanceKm = l.User!.DistanceKm,
                l.CellCount,
                l.AreaM2,
            })
            .ToListAsync();

        return topEntries.Select((e, i) => new LeaderboardEntryResponse
        {
            Rank = i + 1,
            UserId = e.UserId,
            UserName = e.UserName,
            UserColor = e.UserColor,
            UserAvatar = e.UserAvatar,
            UserHexCount = e.UserHexCount,
            UserStreak = e.UserStreak,
            UserDistanceKm = e.UserDistanceKm,
            CellCount = e.CellCount,
            AreaM2 = e.AreaM2,
        }).ToList();
    }

    private async Task<MyRankResponse?> ResolveUserRank(
        Guid? userId, List<LeaderboardEntryResponse> topList,
        IQueryable<LeaderboardEntry> query, DateOnly today)
    {
        if (!userId.HasValue) return null;

        var inTop = topList.FirstOrDefault(e => e.UserId == userId.Value);
        if (inTop != null)
        {
            return new MyRankResponse { Rank = inTop.Rank, CellCount = inTop.CellCount, AreaM2 = inTop.AreaM2 };
        }

        var globalEntry = await _db.LeaderboardEntries
            .Where(l => l.Date == today && l.UserId == userId.Value)
            .Select(l => new { l.CellCount, l.AreaM2 })
            .FirstOrDefaultAsync();

        if (globalEntry == null) return null;

        var higherCount = await query.CountAsync(l => l.CellCount > globalEntry.CellCount);
        return new MyRankResponse
        {
            Rank = higherCount + 1,
            CellCount = globalEntry.CellCount,
            AreaM2 = globalEntry.AreaM2,
        };
    }

    private async Task UpdateAchievementCounters(List<LeaderboardEntry> entries)
    {
        foreach (var entry in entries)
        {
            var user = await _db.Users.FindAsync(entry.UserId);
            if (user == null) continue;

            if (entry.Rank <= 3) user.TopThreeFinishes++;
            if (entry.Rank <= 10) user.TopTenFinishes++;
            if (entry.Rank <= 100) user.TopHundredFinishes++;
            if (entry.Rank <= 1000) user.TopThousandFinishes++;
        }
    }

    private async Task PurgeOldEntries(DateOnly today)
    {
        var cutoff = today.AddDays(-GameConstants.LeaderboardRetentionDays);
        await _db.LeaderboardEntries.Where(l => l.Date < cutoff).ExecuteDeleteAsync();
    }
}
