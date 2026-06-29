namespace MyLoop.Api.Models;

public class ClaimRequest
{
    public Guid UserId { get; set; }
    public double[][] Path { get; set; } = [];

    /// <summary>
    /// Client-generated walk session id (UUID). All batch-step claims and the final
    /// loop claim for one continuous walk share this id, so the server records them as a
    /// single Claim (one walk = one history entry, #56). Defaults to <see cref="Guid.Empty"/>
    /// for older clients, which the server treats as a standalone single-batch claim.
    /// </summary>
    public Guid WalkSessionId { get; set; }
}
