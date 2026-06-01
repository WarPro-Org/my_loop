namespace MyLoop.Api.Interfaces;

/// <summary>
/// Sends push notifications to users via Firebase Cloud Messaging.
/// </summary>
public interface IPushNotificationService
{
    /// <summary>
    /// Notifies a user that their hexes were stolen.
    /// </summary>
    Task NotifyHexStolen(Guid victimUserId, string thiefDisplayName, int stolenCount);

    /// <summary>
    /// Registers or updates a device token for a user.
    /// </summary>
    Task RegisterDeviceToken(Guid userId, string token, string platform);
}
