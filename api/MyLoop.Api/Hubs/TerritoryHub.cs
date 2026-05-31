using Microsoft.AspNetCore.SignalR;

namespace MyLoop.Api.Hubs;

/// <summary>
/// SignalR hub for real-time territory updates.
/// Clients join geographic region groups (H3 resolution-3 parent cells)
/// and receive broadcasts when hex ownership changes in their area.
/// NOTE: No [Authorize] — territory map state is public data. Auth would
/// require complex WebSocket token plumbing with no security benefit.
/// </summary>
public class TerritoryHub : Hub
{
    /// <summary>
    /// Client calls this to subscribe to a geographic region.
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
}
