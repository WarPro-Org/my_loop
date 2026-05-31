namespace MyLoop.Api.Models;

public class UserProfileResponse
{
    public Guid Id { get; set; }
    public string DisplayName { get; set; } = "";
    public string Color { get; set; } = "";
    public int AvatarId { get; set; }
    public int HexCount { get; set; }
    public int Streak { get; set; }
    public int MaxStreak { get; set; }
    public double DistanceKm { get; set; }
    public int TopThreeFinishes { get; set; }
    public int TopTenFinishes { get; set; }
    public int TopHundredFinishes { get; set; }
    public int TopThousandFinishes { get; set; }
    public bool IsStreakActive { get; set; }
    public DateTime JoinedAt { get; set; }
    public int CurrentRank { get; set; }
    public int TotalPlayers { get; set; }
}
