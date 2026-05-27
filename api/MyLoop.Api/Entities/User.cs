namespace MyLoop.Api.Entities;

/// A player in the game. Each user has a unique color and avatar.
public class User
{
    public Guid Id { get; set; }
    public required string FirebaseUid { get; set; }
    public required string DisplayName { get; set; }
    public required string Color { get; set; } // hex color like "#FF5733"
    public int AvatarId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
