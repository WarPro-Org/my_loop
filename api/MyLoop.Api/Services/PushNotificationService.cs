using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;

namespace MyLoop.Api.Services;

/// <summary>
/// Push notification service using Firebase Cloud Messaging.
/// Currently stores tokens and queues notifications.
/// FCM HTTP v1 API integration requires a Firebase service account key
/// configured in appsettings.json (deferred until Firebase project is set up).
/// </summary>
public class PushNotificationService : IPushNotificationService
{
    private readonly AppDbContext _db;
    private readonly ILogger<PushNotificationService> _logger;

    public PushNotificationService(AppDbContext db, ILogger<PushNotificationService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task NotifyHexStolen(Guid victimUserId, string thiefDisplayName, int stolenCount)
    {
        var tokens = await _db.DeviceTokens
            .Where(t => t.UserId == victimUserId)
            .Select(t => t.Token)
            .ToListAsync();

        if (tokens.Count == 0) return;

        var title = "Territory Under Attack! ⚔️";
        var body = stolenCount == 1
            ? $"{thiefDisplayName} captured one of your hexes!"
            : $"{thiefDisplayName} captured {stolenCount} of your hexes!";

        foreach (var token in tokens)
        {
            await SendFcmNotification(token, title, body);
        }
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

    private Task SendFcmNotification(string token, string title, string body)
    {
        // TODO: Implement FCM HTTP v1 API call when Firebase service account is configured.
        // For now, log the notification that would be sent.
        _logger.LogInformation(
            "PUSH [{Token}]: {Title} — {Body}",
            token[..Math.Min(token.Length, 10)], title, body);
        return Task.CompletedTask;
    }
}
