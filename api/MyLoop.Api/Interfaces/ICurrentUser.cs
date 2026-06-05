namespace MyLoop.Api.Interfaces;

/// <summary>
/// Single source of truth for "who is making this request", resolved from the
/// validated Firebase JWT — never from a user id supplied in the request body or route.
///
/// Controllers MUST derive the acting user from here. New endpoints get secure-by-default
/// identity simply by depending on this abstraction, which is why all authorization flows
/// through one place as the codebase grows.
/// </summary>
public interface ICurrentUser
{
    /// <summary>The Firebase UID from the token claims, or null when unauthenticated.</summary>
    string? FirebaseUid { get; }

    /// <summary>
    /// Resolves the internal <c>User.Id</c> for the authenticated caller, or null when the
    /// request is unauthenticated or no matching user exists. Memoized per-request and cached
    /// in memory (5 min) so this does not hit the database on every call.
    /// </summary>
    Task<Guid?> TryGetUserIdAsync();
}
