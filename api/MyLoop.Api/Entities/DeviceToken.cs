namespace MyLoop.Api.Entities;

/// <summary>
/// Stores a user's FCM device token for push notifications.
/// A user can have multiple tokens (multiple devices).
/// </summary>
public class DeviceToken
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required string Token { get; set; }
    public string Platform { get; set; } = "ios"; // "ios" or "android"
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastUsedAt { get; set; } = DateTime.UtcNow;
}
