using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Interfaces;

/// <summary>
/// User operations — registration, lookup, profile updates.
/// </summary>
public interface IUserService
{
    Task<User> Register(RegisterRequest request);
    Task<User?> GetById(Guid id);
    Task<User?> GetByFirebaseUid(string firebaseUid);
    Task<User?> UpdateProfile(Guid id, UpdateUserRequest request);
    Task<UserProfileResponse?> GetRichProfile(Guid id);
    Task<bool> DeleteAccount(Guid userId);
}
