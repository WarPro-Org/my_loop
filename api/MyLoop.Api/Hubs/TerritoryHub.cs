using Microsoft.AspNetCore.SignalR;

namespace MyLoop.Api.Hubs;

/// <summary>
/// SignalR hub for real-time territory updates.
/// Clients join geographic region groups (H3 resolution-3 parent cells)
/// for public map updates, and a personal user group for private state deltas.
/// Connection does NOT require auth (public map events work without login).
/// Personal group methods validate auth via Context.User claim.
/// </summary>
public class TerritoryHub : Hub
{
    /// <summary>
    /// Client calls this to subscribe to a geographic region (public map events).
    /// Region ID = H3 res-3 parent cell ID (covers ~12,000 km²).
    /// </summary>
    public async Task JoinRegion(string regionId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, regionId);
    }

    /// <summary>
    /// Client calls this to unsubscribe from a region (e.g., when panning away).
    /// </summary>
    public async Task LeaveRegion(string regionId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, regionId);
    }

    /// <summary>
    /// Client calls this after auth to subscribe to personal state deltas.
    /// Group name: "user_{userId}" — receives UserStatsDelta, XpDelta, MissionDelta, AchievementUnlocked.
    /// Validates caller is authenticated (token passed via query string on connect).
    /// </summary>
    public async Task JoinUserGroup(string userId)
    {
        // Only authenticated connections can join personal groups
        if (Context.User?.Identity?.IsAuthenticated != true)
        {
            throw new HubException("Authentication required for personal group subscription.");
        }
        await Groups.AddToGroupAsync(Context.ConnectionId, $"user_{userId}");
    }

    /// <summary>
    /// Client calls this to leave personal group (e.g., on logout).
    /// </summary>
    public async Task LeaveUserGroup(string userId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"user_{userId}");
    }
}
