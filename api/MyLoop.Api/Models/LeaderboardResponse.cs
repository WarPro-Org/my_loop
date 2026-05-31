namespace MyLoop.Api.Models;

public class LeaderboardEntryResponse
{
    public int Rank { get; set; }
    public Guid UserId { get; set; }
    public string UserName { get; set; } = "";
    public string UserColor { get; set; } = "";
    public int UserAvatar { get; set; }
    public int UserHexCount { get; set; }
    public int UserStreak { get; set; }
    public double UserDistanceKm { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
}

public class MyRankResponse
{
    public int Rank { get; set; }
    public int CellCount { get; set; }
    public double AreaM2 { get; set; }
}

public class LeaderboardResponse
{
    public List<LeaderboardEntryResponse> Top { get; set; } = [];
    public MyRankResponse? MyRank { get; set; }
    public string Scope { get; set; } = "city";
}
