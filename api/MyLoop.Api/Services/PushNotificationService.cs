using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Interfaces;

namespace MyLoop.Api.Services;

/// <summary>
/// Push notification service using Firebase Cloud Messaging. Sends via the injected
/// <see cref="IFcmSender"/> (real Firebase Admin SDK or a logging no-op, depending on
/// <c>Push:Enabled</c> — see <c>ServiceRegistrationExtensions</c>) and prunes device
/// tokens FCM reports as no longer registered.
/// </summary>
public class PushNotificationService : IPushNotificationService
{
    private readonly AppDbContext _db;
    private readonly IFcmSender _fcmSender;
    private readonly ILogger<PushNotificationService> _logger;

    private const string AnonymousActor = "A player";

    public PushNotificationService(AppDbContext db, IFcmSender fcmSender, ILogger<PushNotificationService> logger)
    {
        _db = db;
        _fcmSender = fcmSender;
        _logger = logger;
    }

    public async Task NotifyHexStolen(Guid victimUserId, Guid thiefUserId, string thiefDisplayName, int stolenCount)
    {
        var tokens = await _db.DeviceTokens
            .Where(t => t.UserId == victimUserId)
            .Select(t => t.Token)
            .ToListAsync();

        if (tokens.Count == 0) return;

        // A blocked player's name never reaches the blocker's lock screen (Guideline 1.2).
        var blocked = await _db.UserBlocks.AnyAsync(b => b.BlockerId == victimUserId && b.BlockedId == thiefUserId);
        var actor = blocked ? AnonymousActor : thiefDisplayName;

        var title = "Territory Under Attack! ⚔️";
        var body = stolenCount == 1
            ? $"{actor} captured one of your hexes!"
            : $"{actor} captured {stolenCount} of your hexes!";

        IReadOnlyList<FcmSendOutcome> outcomes;
        try
        {
            outcomes = await _fcmSender.SendEachAsync(tokens, title, body);
        }
        catch (Exception ex)
        {
            // Post-commit best-effort: territory has already changed hands, so a push failure
            // must never surface as an error to the thief's claim request.
            _logger.LogWarning(ex, "FCM send failed for user {UserId}; territory theft already committed", victimUserId);
            return;
        }

        var deadTokens = outcomes.Where(o => o.IsUnregistered).Select(o => o.Token).ToList();
        if (deadTokens.Count == 0) return;

        await _db.DeviceTokens
            .Where(t => t.UserId == victimUserId && deadTokens.Contains(t.Token))
            .ExecuteDeleteAsync();
    }

    public async Task RegisterDeviceToken(Guid userId, string token, string platform)
    {
        var existing = await _db.DeviceTokens
            .FirstOrDefaultAsync(t => t.Token == token);

        if (existing != null)
        {
            existing.UserId = userId;
            existing.LastUsedAt = DateTime.UtcNow;
        }
        else
        {
            _db.DeviceTokens.Add(new DeviceToken
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Token = token,
                Platform = platform,
                CreatedAt = DateTime.UtcNow,
                LastUsedAt = DateTime.UtcNow,
            });
        }

        await _db.SaveChangesAsync();
    }
}
