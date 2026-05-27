namespace MyLoop.Api.Entities;

/// <summary>
/// Represents a player in the MyLoop territory game.
/// Each user is identified by their Firebase Auth UID and has a customizable
/// appearance (color + avatar) that is displayed on the territory map and leaderboard.
/// </summary>
public class User
{
    /// <summary>Internal unique identifier for the user (primary key).</summary>
    public Guid Id { get; set; }

    /// <summary>Firebase Authentication UID — links this user to their Firebase identity. Must be unique.</summary>
    public required string FirebaseUid { get; set; }

    /// <summary>Player-chosen display name shown on the map and leaderboard.</summary>
    public required string DisplayName { get; set; }

    /// <summary>Hex color string (e.g., "#FF5733") used to render this player's territory on the map.</summary>
    public required string Color { get; set; }

    /// <summary>Index of the player's selected avatar graphic from the predefined avatar set.</summary>
    public int AvatarId { get; set; }

    /// <summary>Timestamp when the user account was created (defaults to UTC now).</summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
