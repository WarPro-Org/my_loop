namespace MyLoop.Api.Interfaces;

/// <summary>Result of blocking a player.</summary>
public enum BlockOutcome
{
    Done,
    SelfBlock,
    NotFound,
    LimitReached,
}

/// <summary>Per-player identity blocks (DR-002b, #190). Never affects gameplay.</summary>
public interface IBlockService
{
    Task<IReadOnlyList<Guid>> ListBlockedAsync(Guid blockerId);
    /// <summary>Idempotent: blocking an already-blocked player is <see cref="BlockOutcome.Done"/>.</summary>
    Task<BlockOutcome> BlockAsync(Guid blockerId, Guid blockedId);
    /// <summary>Idempotent: unblocking someone not blocked is a no-op.</summary>
    Task UnblockAsync(Guid blockerId, Guid blockedId);
}
