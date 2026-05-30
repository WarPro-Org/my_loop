using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// User operations — registration, lookup, profile updates.
/// </summary>
public class UserService : IUserService
{
    private readonly AppDbContext _db;
    private readonly IValidationService _validation;

    public UserService(AppDbContext db, IValidationService validation)
    {
        _db = db;
        _validation = validation;
    }

    public async Task<User> Register(RegisterRequest request)
    {
        var authProvider = request.AuthProvider ?? "local";
        var firebaseUid = request.FirebaseUid;

        // For local accounts, generate a unique UID if not provided
        if (string.IsNullOrWhiteSpace(firebaseUid)
            || firebaseUid.StartsWith("dev_")
            || firebaseUid.StartsWith("local_"))
        {
            firebaseUid = $"local_{Guid.NewGuid():N}";
            authProvider = "local";
        }

        // Check if user already exists — return existing (graceful re-registration)
        var existing = await _db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);
        if (existing != null)
        {
            return existing;
        }

        var user = new User
        {
            Id = Guid.NewGuid(),
            FirebaseUid = firebaseUid,
            DisplayName = request.DisplayName.Trim(),
            Color = request.Color,
            AvatarId = request.AvatarId,
            AuthProvider = authProvider,
        };

        _db.Users.Add(user);
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (Microsoft.EntityFrameworkCore.DbUpdateException)
        {
            // Race condition: another request registered this UID between our check and insert.
            // Detach the failed entity and return the existing one.
            _db.Entry(user).State = Microsoft.EntityFrameworkCore.EntityState.Detached;
            var raced = await _db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);
            if (raced != null) return raced;
            throw; // Truly unexpected — rethrow
        }
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

    public async Task<User?> UpdateProfile(Guid id, UpdateUserRequest request)
    {
        var user = await _db.Users.FindAsync(id);
        if (user == null) return null;

        if (request.DisplayName != null)
        {
            user.DisplayName = request.DisplayName.Trim();
        }
        if (request.Color != null)
        {
            user.Color = request.Color;
        }
        if (request.AvatarId != null)
        {
            user.AvatarId = request.AvatarId.Value;
        }

        await _db.SaveChangesAsync();
        return user;
    }

    public async Task<UserProfileResponse?> GetRichProfile(Guid id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user == null) return null;

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        // Get current rank from today's leaderboard
        var entry = await _db.LeaderboardEntries
            .Where(l => l.Date == today && l.UserId == id)
            .FirstOrDefaultAsync();
        var currentRank = entry?.Rank ?? 0;

        // Count total players for "out of X" display
        var totalPlayers = await _db.LeaderboardEntries
            .Where(l => l.Date == today)
            .CountAsync();

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
            CurrentRank = currentRank,
            TotalPlayers = totalPlayers,
        };
    }
}
