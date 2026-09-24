using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Interfaces;
using Npgsql;

namespace MyLoop.Api.Services.Moderation;

/// <summary>Stores who has blocked whom (DR-002b, #190).</summary>
public sealed class BlockService(AppDbContext db) : IBlockService
{
    /// <summary>A row referenced a <c>Users</c> row that no longer exists.</summary>
    private const string ForeignKeyViolation = PostgresErrorCodes.ForeignKeyViolation; // 23503

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

        try
        {
            // EnableRetryOnFailure requires explicit transactions to run inside the execution
            // strategy. The block is idempotent: a retry after an ambiguous commit finds the row
            // and returns Done.
            return await db.Database.CreateExecutionStrategy()
                .ExecuteAsync(() => InsertWithinLimitAsync(blockerId, blockedId));
        }
        catch (PostgresException e) when (e.SqlState == ForeignKeyViolation)
        {
            // The target deleted their account between the check above and the insert.
            return BlockOutcome.NotFound;
        }
    }

    private async Task<BlockOutcome> InsertWithinLimitAsync(Guid blockerId, Guid blockedId)
    {
        db.ChangeTracker.Clear();
        await using var tx = await db.Database.BeginTransactionAsync();

        // Serialises this blocker's blocks, so N concurrent requests can't each see a count below
        // the limit and all insert (#195 review). Other blockers are not held up.
        await ModerationLocks.LockBlockerAsync(db, blockerId);

        if (await db.UserBlocks.AnyAsync(b => b.BlockerId == blockerId && b.BlockedId == blockedId))
            return BlockOutcome.Done;
        if (await db.UserBlocks.CountAsync(b => b.BlockerId == blockerId) >= GameConstants.MaxBlocksPerUser)
            return BlockOutcome.LimitReached;

        await db.Database.ExecuteSqlInterpolatedAsync($@"
            INSERT INTO ""UserBlocks"" (""BlockerId"", ""BlockedId"", ""CreatedAt"")
            VALUES ({blockerId}, {blockedId}, {DateTime.UtcNow})
            ON CONFLICT (""BlockerId"", ""BlockedId"") DO NOTHING");
        await tx.CommitAsync();
        return BlockOutcome.Done;
    }

    public Task UnblockAsync(Guid blockerId, Guid blockedId) =>
        db.UserBlocks.Where(b => b.BlockerId == blockerId && b.BlockedId == blockedId).ExecuteDeleteAsync();
}
