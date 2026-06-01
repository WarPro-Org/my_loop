using Microsoft.AspNetCore.SignalR;
using MyLoop.Api.Hubs;
using MyLoop.Api.Interfaces;

namespace MyLoop.Api.Services;

/// <summary>
/// Broadcasts hex ownership changes (public, region-scoped) and personal
/// state deltas (per-user group) via SignalR.
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

    public async Task NotifyUserStatsAsync(Guid userId, UserStatsDelta delta)
    {
        await _hubContext.Clients
            .Group($"user_{userId}")
            .SendAsync("UserStatsDelta", delta);

        _logger.LogDebug("Pushed UserStatsDelta to user {UserId}: HexCount={HexCount}",
            userId, delta.HexCount);
    }

    public async Task NotifyXpAsync(Guid userId, XpDelta delta)
    {
        await _hubContext.Clients
            .Group($"user_{userId}")
            .SendAsync("XpDelta", delta);

        _logger.LogDebug("Pushed XpDelta to user {UserId}: +{XpGained} XP, Level={Level}",
            userId, delta.XpGained, delta.Level);
    }

    public async Task NotifyMissionAsync(Guid userId, MissionDelta delta)
    {
        if (delta.Updates.Count == 0) return;

        await _hubContext.Clients
            .Group($"user_{userId}")
            .SendAsync("MissionDelta", delta);

        _logger.LogDebug("Pushed MissionDelta to user {UserId}: {Count} mission updates",
            userId, delta.Updates.Count);
    }

    public async Task NotifyAchievementAsync(Guid userId, AchievementDelta delta)
    {
        if (delta.Unlocks.Count == 0) return;

        await _hubContext.Clients
            .Group($"user_{userId}")
            .SendAsync("AchievementUnlocked", delta);

        _logger.LogDebug("Pushed AchievementUnlocked to user {UserId}: {Count} unlocks",
            userId, delta.Unlocks.Count);
    }
}
