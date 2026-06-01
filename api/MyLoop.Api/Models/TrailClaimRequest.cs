namespace MyLoop.Api.Models;

public class TrailClaimRequest
{
    public Guid UserId { get; set; }
    public double[][] Points { get; set; } = [];
}

/// <summary>
/// Single GPS point claim — server computes which H3 hex this falls in,
/// claims it if new, and returns the boundary for instant rendering.
/// </summary>
public class StepClaimRequest
{
    public Guid UserId { get; set; }
    public double Lat { get; set; }
    public double Lng { get; set; }
}
