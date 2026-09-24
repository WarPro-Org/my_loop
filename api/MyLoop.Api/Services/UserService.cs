using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Models;
using MyLoop.Api.Services.Moderation;

namespace MyLoop.Api.Services;

public class UserService : IUserService
{
    private readonly AppDbContext _db;
    private readonly IValidationService _validation;
    private readonly ILogger<UserService> _logger;

    public UserService(AppDbContext db, IValidationService validation, ILogger<UserService> logger)
    {
        _db = db;
        _validation = validation;
        _logger = logger;
    }

    public async Task<User> Register(RegisterRequest request, string firebaseUid, string authProvider)
    {
        var existing = await _db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);
        if (existing != null) return existing;

        var user = BuildNewUser(firebaseUid, authProvider, request);
        _db.Users.Add(user);

        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return await HandleRegistrationRace(user, firebaseUid);
        }

        await CreateInitialLeaderboardEntry(user.Id);
        return user;
    }

    public async Task<User?> GetById(Guid id)
    {
        return await _db.Users.FindAsync(id);
    }

    public async Task<User?> GetByFirebaseUid(string firebaseUid)
    {
        return await _db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);
    }

    public Task<ProfileUpdateResult> UpdateProfile(Guid id, UpdateUserRequest request) =>
        // EnableRetryOnFailure requires explicit transactions to run inside the execution strategy.
        // The block is idempotent: it re-reads the user after Clear() and only assigns values.
        _db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            _db.ChangeTracker.Clear();
            await using var transaction = await _db.Database.BeginTransactionAsync();

            string? newName = null;
            if (request.DisplayName != null)
            {
                // Same lock, taken first, as reports, confirm, restore and rescan: a hide or a
                // moderator decision can then no longer commit between the check and the save.
                await ModerationLocks.LockUserAsync(_db, id);
                newName = ValidationService.NormalizeDisplayName(request.DisplayName);
                switch (await RenameGate.CheckAsync(_db, id, newName))
                {
                    case RenameCheck.Locked: return new ProfileUpdateResult(ProfileUpdateStatus.NameLocked);
                    case RenameCheck.RemovedName: return new ProfileUpdateResult(ProfileUpdateStatus.NameRemoved);
                }
            }

            // Loaded after the lock, so it reflects any hide that committed before we took it.
            var user = await _db.Users.FindAsync(id);
            if (user == null) return new ProfileUpdateResult(ProfileUpdateStatus.NotFound);

            if (newName != null) ApplyRename(user, newName);
            if (request.Color != null) user.Color = request.Color;
            if (request.AvatarId != null) user.AvatarId = request.AvatarId.Value;

            await _db.SaveChangesAsync();
            await transaction.CommitAsync();
            return new ProfileUpdateResult(ProfileUpdateStatus.Updated, user);
        });

    public async Task<UserProfileResponse?> GetRichProfile(Guid id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user == null) return null;

        var (rank, totalPlayers) = await GetCurrentRanking(id);
        return MapToProfileResponse(user, rank, totalPlayers);
    }

    public async Task<bool> DeleteAccount(Guid userId)
    {
        // The purge is 8 separate ExecuteDeleteAsync statements plus the user row's own
        // delete — wrapped in one transaction (under CreateExecutionStrategy so Neon's
        // EnableRetryOnFailure can still retry a dropped connection) so a mid-sequence
        // failure leaves nothing deleted instead of an orphaned partial purge (#122).
        var strategy = _db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync(async () =>
        {
            _db.ChangeTracker.Clear();
            await using var transaction = await _db.Database.BeginTransactionAsync();
            try
            {
                var user = await _db.Users.FindAsync(userId);
                if (user == null)
                {
                    await transaction.RollbackAsync();
                    return false;
                }

                await DeleteUserData(userId);
                _db.Users.Remove(user);
                await _db.SaveChangesAsync();
                await transaction.CommitAsync();
                return true;
            }
            catch
            {
                // Preserve the original exception for the execution strategy to classify —
                // a rollback on a dropped connection would otherwise throw and mask it.
                try
                {
                    await transaction.RollbackAsync();
                }
                catch (Exception rollbackEx)
                {
                    _logger.LogWarning(rollbackEx,
                        "Rollback after a failed account deletion also failed for user {UserId}; surfacing the original error",
                        userId);
                }
                throw;
            }
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ──────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// A chosen name replaces any moderation placeholder (#190). Both columns are always written:
    /// EF skips a property whose value equals the one it loaded, and a rename must never leave a
    /// stale NameHiddenAt, or the name it hid, in place.
    /// </summary>
    private void ApplyRename(User user, string newName)
    {
        user.DisplayName = newName;
        user.NameHiddenAt = null;
        var entry = _db.Entry(user);
        entry.Property(u => u.DisplayName).IsModified = true;
        entry.Property(u => u.NameHiddenAt).IsModified = true;
    }

    private static User BuildNewUser(string firebaseUid, string authProvider, RegisterRequest request)
    {
        return new User
        {
            Id = Guid.NewGuid(),
            FirebaseUid = firebaseUid,
            DisplayName = ValidationService.NormalizeDisplayName(request.DisplayName),
            Color = request.Color,
            AvatarId = request.AvatarId,
            AuthProvider = authProvider,
        };
    }

    private async Task<User> HandleRegistrationRace(User failedUser, string firebaseUid)
    {
        _db.Entry(failedUser).State = EntityState.Detached;
        var raced = await _db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);
        return raced ?? throw new InvalidOperationException("Unexpected registration failure");
    }

    private async Task CreateInitialLeaderboardEntry(Guid userId)
    {
        // Join the CURRENT visible snapshot, not raw UTC today: a today-dated row written
        // before the day's first refresh would become the newest "snapshot" and hide the
        // real board from every reader until the refresh runs (#125).
        var snapshotDate = await LeaderboardService.LatestSnapshotDate(_db);

        // Rank the newcomer the way every reader computes rank (#167): count of strictly higher
        // cell counts, plus one. They have zero cells, so that is however many players on this
        // snapshot have captured anything — and all other zero-cell players get the same number,
        // because they are genuinely tied.
        //
        // This used to be the total user count (#139 D7), which invented a rank twice over: it
        // counted users with no row on this snapshot at all, so a newcomer could be told they were
        // 1000th on a 51-row board, and it handed every zero-cell player a different rank. The
        // value is short-lived — the next leaderboard refresh overwrites it — but it is what the
        // profile tile shows a brand-new player, which is the one moment they have no other
        // reference for whether the number is sane.
        var rank = await _db.LeaderboardEntries
            .CountAsync(l => l.Date == snapshotDate && l.CellCount > 0) + 1;

        _db.Set<LeaderboardEntry>().Add(new LeaderboardEntry
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Date = snapshotDate,
            CellCount = 0,
            AreaM2 = 0,
            Rank = rank,
        });
        await _db.SaveChangesAsync();
    }

    private async Task<(int Rank, int TotalPlayers)> GetCurrentRanking(Guid userId)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        // Same blank-window fallback as the leaderboard (#125): between UTC midnight and the
        // day's first refresh "today" has no rows, which zeroed the profile's rank tile.
        var snapshotDate = await LeaderboardService.LatestSnapshotDate(_db);

        var entry = await _db.LeaderboardEntries
            .Where(l => l.Date == snapshotDate && l.UserId == userId)
            .FirstOrDefaultAsync();

        var totalPlayers = await _db.LeaderboardEntries
            .Where(l => l.Date == snapshotDate)
            .CountAsync();

        return (entry?.Rank ?? 0, totalPlayers);
    }

    private static UserProfileResponse MapToProfileResponse(User user, int rank, int totalPlayers)
    {
        return new UserProfileResponse
        {
            Id = user.Id,
            DisplayName = user.DisplayName,
            Color = user.Color,
            AvatarId = user.AvatarId,
            HexCount = user.HexCount,
            Streak = user.Streak,
            MaxStreak = user.MaxStreak,
            DistanceKm = user.DistanceKm,
            TopThreeFinishes = user.TopThreeFinishes,
            TopTenFinishes = user.TopTenFinishes,
            TopHundredFinishes = user.TopHundredFinishes,
            TopThousandFinishes = user.TopThousandFinishes,
            IsStreakActive = user.IsStreakActive,
            JoinedAt = user.CreatedAt,
            CurrentRank = rank,
            TotalPlayers = totalPlayers,
        };
    }

    /// <summary>
    /// Removes ALL data belonging to a user prior to deleting the account row.
    /// There are no DB-level FK cascades configured (see <see cref="AppDbContext"/>),
    /// so every child table that carries a UserId MUST be purged explicitly here —
    /// otherwise account deletion silently orphans the user's rows (a privacy
    /// violation given the App Store "delete my data" guarantee in the privacy policy).
    /// </summary>
    private async Task DeleteUserData(Guid userId)
    {
        await _db.TerritoryCells.Where(c => c.OwnerId == userId).ExecuteDeleteAsync();
        await _db.Set<CellTransfer>().Where(t => t.FromUserId == userId || t.ToUserId == userId).ExecuteDeleteAsync();
        await _db.Claims.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await _db.LeaderboardEntries.Where(l => l.UserId == userId).ExecuteDeleteAsync();
        // Previously orphaned — these carry per-user (and PII-adjacent) data:
        await _db.ExploredCells.Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await _db.DailyMissions.Where(m => m.UserId == userId).ExecuteDeleteAsync();
        await _db.UserAchievements.Where(a => a.UserId == userId).ExecuteDeleteAsync();
        await _db.DeviceTokens.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        // Name moderation (#190). These tables do cascade at the DB level, but are purged here too
        // so this method stays the one complete list and never depends on the FK definition.
        // Both directions: reports this player filed, and reports about them.
        await _db.NameReports.Where(r => r.ReporterId == userId || r.ReportedUserId == userId).ExecuteDeleteAsync();
        await _db.NameModerationCases.Where(c => c.UserId == userId).ExecuteDeleteAsync();
    }
}
