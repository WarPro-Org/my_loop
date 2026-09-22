using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Interfaces;

namespace MyLoop.Api.Services.Moderation;

/// <summary>Stores who has blocked whom (DR-002b, #190).</summary>
public sealed class BlockService(AppDbContext db) : IBlockService
{
    public async Task<IReadOnlyList<Guid>> ListBlockedAsync(Guid blockerId) =>
        await db.UserBlocks.AsNoTracking()
            .Where(b => b.BlockerId == blockerId)
            .OrderBy(b => b.CreatedAt)
            .Select(b => b.BlockedId)
            .ToListAsync();

    public async Task<BlockOutcome> BlockAsync(Guid blockerId, Guid blockedId)
    {
        if (blockerId == blockedId) return BlockOutcome.SelfBlock;
        if (!await db.Users.AnyAsync(u => u.Id == blockedId)) return BlockOutcome.NotFound;
        if (await db.UserBlocks.AnyAsync(b => b.BlockerId == blockerId && b.BlockedId == blockedId))
            return BlockOutcome.Done;
        // Two simultaneous blocks can overshoot the cap by one — acceptable for a list-size bound.
        if (await db.UserBlocks.CountAsync(b => b.BlockerId == blockerId) >= GameConstants.MaxBlocksPerUser)
            return BlockOutcome.LimitReached;

        await db.Database.ExecuteSqlInterpolatedAsync($@"
            INSERT INTO ""UserBlocks"" (""BlockerId"", ""BlockedId"", ""CreatedAt"")
            VALUES ({blockerId}, {blockedId}, {DateTime.UtcNow})
            ON CONFLICT (""BlockerId"", ""BlockedId"") DO NOTHING");
        return BlockOutcome.Done;
    }

    public Task UnblockAsync(Guid blockerId, Guid blockedId) =>
        db.UserBlocks.Where(b => b.BlockerId == blockerId && b.BlockedId == blockedId).ExecuteDeleteAsync();
}
