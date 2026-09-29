using Microsoft.AspNetCore.SignalR;
using MyLoop.Api.Hubs;
using MyLoop.Api.Interfaces;

namespace MyLoop.Api.Services;

/// <summary>
/// Sends hex ownership changes and personal state deltas via SignalR, always to the
/// affected player's own group only (single-player 0.1, bug B1).
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

        // Single-player 0.1 (bug B1): each player hears only about their own hexes. The new owner
        // gets the change; a previous owner only learns the hex left their map, never who took it.
        foreach (var ownerGroup in changes.GroupBy(c => c.NewOwnerId))
        {
            var payload = ownerGroup.Select(c => new
            {
                c.H3Index,
                c.CenterLat,
                c.CenterLng,
                c.NewOwnerId,
                c.NewOwnerColor,
                c.NewOwnerDisplayName,
                c.PreviousOwnerId,
            }).ToList();
            await SafeSendToUser(ownerGroup.Key, "HexOwnershipChanged", payload, "HexOwnershipChanged");
        }

        var lost = changes
            .Where(c => c.PreviousOwnerId is { } previous && previous != c.NewOwnerId)
            .Select(c => new HexReleasedEvent(c.H3Index, c.ParentCellId, c.PreviousOwnerId!.Value))
            .ToList();
        await NotifyHexesReleasedAsync(lost);
    }

    public async Task NotifyHexesReleasedAsync(IReadOnlyList<HexReleasedEvent> released)
    {
        // One payload per owner and region, in the shape clients already parse (#104).
        foreach (var group in released.GroupBy(r => (r.OwnerId, r.ParentCellId)))
        {
            var payload = new
            {
                ParentCellId = group.Key.ParentCellId.ToString(),
                H3Indexes = group.Select(r => r.H3Index).ToList(),
            };
            await SafeSendToUser(group.Key.OwnerId, "HexesReleased", payload, "HexesReleased");
        }
    }

    public Task NotifyUserStatsAsync(Guid userId, UserStatsDelta delta) =>
        SafeSendToUser(userId, "UserStatsDelta", delta, "UserStatsDelta");

    public Task NotifyXpAsync(Guid userId, XpDelta delta) =>
        SafeSendToUser(userId, "XpDelta", delta, "XpDelta");

    public Task NotifyMissionAsync(Guid userId, MissionDelta delta) =>
        delta.Updates.Count == 0
            ? Task.CompletedTask
            : SafeSendToUser(userId, "MissionDelta", delta, "MissionDelta");

    public Task NotifyAchievementAsync(Guid userId, AchievementDelta delta) =>
        delta.Unlocks.Count == 0
            ? Task.CompletedTask
            : SafeSendToUser(userId, "AchievementUnlocked", delta, "AchievementUnlocked");

    /// <summary>
    /// Sends a personal delta to the user's group, swallowing (but logging) transport
    /// failures so a dropped connection never surfaces as an unobserved task exception
    /// in the fire-and-forget push path (HIGH-10).
    /// </summary>
    private async Task SafeSendToUser<T>(Guid userId, string method, T payload, string label)
    {
        try
        {
            await _hubContext.Clients.Group($"user_{userId}").SendAsync(method, payload);
            _logger.LogDebug("Pushed {Label} to user {UserId}", label, userId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to push {Label} to user {UserId}", label, userId);
        }
    }
}
