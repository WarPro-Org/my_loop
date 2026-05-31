using Microsoft.AspNetCore.SignalR;
using MyLoop.Api.Hubs;

namespace MyLoop.Api.Services;

/// <summary>
/// Broadcasts hex ownership changes via SignalR to clients subscribed to affected regions.
/// Groups are keyed by H3 resolution-3 parent cell ID (string).
/// </summary>
public class TerritoryNotifier : ITerritoryNotifier
{
    private readonly IHubContext<TerritoryHub> _hubContext;
    private readonly ILogger<TerritoryNotifier> _logger;

    public TerritoryNotifier(IHubContext<TerritoryHub> hubContext, ILogger<TerritoryNotifier> logger)
    {
        _hubContext = hubContext;
        _logger = logger;
    }

    public async Task NotifyHexOwnershipChanged(IReadOnlyList<HexChangeEvent> changes)
    {
        if (changes.Count == 0) return;

        // Group changes by parent cell (region) for targeted broadcast
        var byRegion = changes.GroupBy(c => c.ParentCellId.ToString());

        foreach (var regionGroup in byRegion)
        {
            var payload = regionGroup.Select(c => new
            {
                c.H3Index,
                c.CenterLat,
                c.CenterLng,
                c.NewOwnerId,
                c.NewOwnerColor,
                c.NewOwnerDisplayName,
                c.PreviousOwnerId,
            }).ToList();

            await _hubContext.Clients
                .Group(regionGroup.Key)
                .SendAsync("HexOwnershipChanged", payload);
        }

        _logger.LogDebug("Broadcast {Count} hex changes to {RegionCount} regions",
            changes.Count, changes.Select(c => c.ParentCellId).Distinct().Count());
    }
}
