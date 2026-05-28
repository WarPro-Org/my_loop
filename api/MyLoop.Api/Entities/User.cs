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

    /// <summary>Total number of hexes currently owned by this player.</summary>
    public int HexCount { get; set; }

    /// <summary>Current daily walk streak (consecutive days with at least one walk).</summary>
    public int Streak { get; set; }

    /// <summary>Total distance walked in kilometers.</summary>
    public double DistanceKm { get; set; }

    /// <summary>The highest streak this user has ever achieved.</summary>
    public int MaxStreak { get; set; }

    /// <summary>Number of times this user finished in the top 3 of a daily leaderboard.</summary>
    public int TopThreeFinishes { get; set; }

    /// <summary>Whether the user is currently on an active streak today.</summary>
    public bool IsStreakActive { get; set; } = true;

    /// <summary>Timestamp when the user account was created (defaults to UTC now).</summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>The city the user registered in (for city-scope leaderboard).</summary>
    public string City { get; set; } = "";

    /// <summary>The country the user is in (for country-scope leaderboard).</summary>
    public string Country { get; set; } = "";

    /// <summary>Authentication provider used to create this account (e.g., "google", "apple", "local").</summary>
    public string AuthProvider { get; set; } = "local";
}
