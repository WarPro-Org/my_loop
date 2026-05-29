namespace MyLoop.Api.Models;

/// <summary>
/// Request body for user registration.
/// </summary>
public class RegisterRequest
{
    public string? FirebaseUid { get; set; }
    public string DisplayName { get; set; } = "";
    public string Color { get; set; } = "";
    public int AvatarId { get; set; }
    public string? AuthProvider { get; set; } = "local";
}

/// <summary>
/// Request body for updating a user's profile. Only non-null fields are applied.
/// </summary>
public class UpdateUserRequest
{
    public string? DisplayName { get; set; }
    public string? Color { get; set; }
    public int? AvatarId { get; set; }
}

/// <summary>
/// Request body for submitting a territory claim.
/// </summary>
public class ClaimRequest
{
    public Guid UserId { get; set; }
    public double[][] Path { get; set; } = [];
}
