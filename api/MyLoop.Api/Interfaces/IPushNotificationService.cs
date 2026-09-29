namespace MyLoop.Api.Interfaces;

/// <summary>
/// Sends push notifications to users via Firebase Cloud Messaging.
/// </summary>
public interface IPushNotificationService
{
    /// <summary>
    /// Notifies a user that their hexes were stolen. Single-player 0.1: the other player is
    /// never named (bug B1).
    /// </summary>
    Task NotifyHexStolen(Guid victimUserId, int stolenCount);

    /// <summary>
    /// Registers or updates a device token for a user.
    /// </summary>
    Task RegisterDeviceToken(Guid userId, string token, string platform);
}
