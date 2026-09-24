using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Interfaces;

/// <summary>What a profile update did.</summary>
public enum ProfileUpdateStatus
{
    Updated,
    NotFound,
    /// <summary>Confirmed strikes lock renaming until a moderator unlocks it (DR-002b §4.2).</summary>
    NameLocked,
    /// <summary>A moderator hid or removed this exact name from this player.</summary>
    NameRemoved,
}

/// <summary>A profile update's outcome; <see cref="User"/> is set only when <see cref="Status"/> is Updated.</summary>
public sealed record ProfileUpdateResult(ProfileUpdateStatus Status, User? User = null);

/// <summary>
/// User operations — registration, lookup, profile updates.
/// </summary>
public interface IUserService
{
    /// <summary>
    /// Creates (or returns the existing) user for the given <paramref name="firebaseUid"/>.
    /// The uid is TRUSTED — the caller (the controller) must have derived it from the validated
    /// Firebase token or minted a server-side local uid, never taken it from the request body
    /// (UsersController.Register, #99).
    /// </summary>
    Task<User> Register(RegisterRequest request, string firebaseUid, string authProvider);
    Task<User?> GetById(Guid id);
    Task<User?> GetByFirebaseUid(string firebaseUid);
    /// <summary>
    /// Applies a validated profile update. A rename runs the moderation checks and the save in one
    /// transaction under the player's row lock, so a hide or moderator decision can't slip between them.
    /// </summary>
    Task<ProfileUpdateResult> UpdateProfile(Guid id, UpdateUserRequest request);
    Task<UserProfileResponse?> GetRichProfile(Guid id);
    Task<bool> DeleteAccount(Guid userId);
}
