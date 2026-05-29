using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

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
}
