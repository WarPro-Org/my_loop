namespace MyLoop.Api.Models;

public class ClaimRequest
{
    public Guid UserId { get; set; }
    public double[][] Path { get; set; } = [];
}
