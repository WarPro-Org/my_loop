using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;

namespace MyLoop.Api.Services.Moderation;

/// <summary>
/// The one row lock every name-changing transaction takes first (reports, moderator
/// confirm/restore, rescan and renames). Taking the same lock in the same order everywhere is what
/// serialises them and keeps them from deadlocking; a case row, if needed, is locked after it.
/// </summary>
internal static class ModerationLocks
{
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
