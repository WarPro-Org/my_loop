using System.Security.Claims;
using Microsoft.Extensions.Caching.Memory;
using MyLoop.Api.Interfaces;

namespace MyLoop.Api.Services;

/// <summary>
/// Resolves the caller's identity from the validated Firebase JWT. See <see cref="ICurrentUser"/>.
/// </summary>
public class CurrentUser : ICurrentUser
{
    private const string ItemsKey = "__CurrentUserId";

    private readonly IHttpContextAccessor _http;
    private readonly IUserService _users;
    private readonly IMemoryCache _cache;

    public CurrentUser(IHttpContextAccessor http, IUserService users, IMemoryCache cache)
    {
        _http = http;
        _users = users;
        _cache = cache;
    }

    public string? FirebaseUid
    {
        get
        {
            var principal = _http.HttpContext?.User;
            if (principal?.Identity?.IsAuthenticated != true) return null;

            // Firebase puts the uid in "user_id"; "sub" is the same value and (with default
            // inbound claim mapping) may surface as ClaimTypes.NameIdentifier.
            return principal.FindFirst(Constants.FirebaseClaims.UserId)?.Value
                ?? principal.FindFirst(Constants.FirebaseClaims.Subject)?.Value
                ?? principal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        }
    }

    public async Task<Guid?> TryGetUserIdAsync()
    {
        var ctx = _http.HttpContext;
        if (ctx is null) return null;

        if (ctx.Items.TryGetValue(ItemsKey, out var memoized) && memoized is Guid memo)
            return memo;

        var uid = FirebaseUid;
        if (string.IsNullOrEmpty(uid)) return null;

        var cacheKey = $"uid->id:{uid}";
        if (!_cache.TryGetValue(cacheKey, out Guid userId))
        {
            var user = await _users.GetByFirebaseUid(uid);
            if (user is null) return null;
            userId = user.Id;
            _cache.Set(cacheKey, userId, TimeSpan.FromMinutes(5));
        }

        ctx.Items[ItemsKey] = userId;
        return userId;
    }
}
