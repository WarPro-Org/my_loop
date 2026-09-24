using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;

namespace MyLoop.Api.Services.Moderation;

/// <summary>
/// The locks moderation transactions take, in this order: a report's reporter lock, then the
/// player's <c>Users</c> row (every name-changing transaction: reports, moderator
/// confirm/restore, rescan and renames), then a case row if needed. Taking them in the same order
/// everywhere is what serialises these transactions and keeps them from deadlocking.
/// </summary>
internal static class ModerationLocks
{
    /// <summary>
    /// First key of the two-key advisory-lock form for "one reporter's name reports". The two-key
    /// space never overlaps the one-key space TerritoryService and LeaderboardService use.
    /// </summary>
    private const int ReporterLockNamespace = 0x4E524550; // "NREP"

    /// <summary>First key of the two-key advisory lock for "one player's blocks".</summary>
    private const int BlockerLockNamespace = 0x55424C4B; // "UBLK"

    /// <summary>
    /// Serialises one reporter's reports until the transaction ends, so the daily-limit count and
    /// the insert can't interleave. Must be the first lock a report takes: it is an advisory lock,
    /// not the reporter's <c>Users</c> row, because other code updates many <c>Users</c> rows in
    /// no fixed order (leaderboard, decay, territory) and a second row lock here could deadlock
    /// with them. Nothing that holds a lock ever waits for this one, so it can't join a cycle.
    /// Two reporters whose keys collide are merely serialised with each other.
    /// </summary>
    public static Task LockReporterAsync(AppDbContext db, Guid reporterId) =>
        db.Database.ExecuteSqlInterpolatedAsync(
            $"SELECT pg_advisory_xact_lock({ReporterLockNamespace}, {BitConverter.ToInt32(reporterId.ToByteArray(), 0)})");

    /// <summary>
    /// Serialises one player's blocks until the transaction ends, so the limit count and the insert
    /// can't interleave. The only lock a block takes, and nothing holding another lock waits for
    /// it, so it can't join a deadlock cycle. Two blockers whose keys collide are merely
    /// serialised with each other.
    /// </summary>
    public static Task LockBlockerAsync(AppDbContext db, Guid blockerId) =>
        db.Database.ExecuteSqlInterpolatedAsync(
            $"SELECT pg_advisory_xact_lock({BlockerLockNamespace}, {BitConverter.ToInt32(blockerId.ToByteArray(), 0)})");

    /// <summary>
    /// Locks the player's <c>Users</c> row until the transaction ends. <c>FOR NO KEY UPDATE</c>
    /// conflicts with itself and with every <c>UPDATE</c>, so it serialises all moderation writes,
    /// but, unlike <c>FOR UPDATE</c>, it does not block the <c>FOR KEY SHARE</c> lock a foreign-key
    /// check takes. Two players reporting each other at once would otherwise deadlock (#194 review).
    /// </summary>
    public static Task LockUserAsync(AppDbContext db, Guid userId) =>
        db.Database.ExecuteSqlInterpolatedAsync(
            $@"SELECT 1 FROM ""Users"" WHERE ""Id"" = {userId} FOR NO KEY UPDATE");
}
