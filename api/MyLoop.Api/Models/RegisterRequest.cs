namespace MyLoop.Api.Models;

public class RegisterRequest
{
    public string? FirebaseUid { get; set; }
    public string DisplayName { get; set; } = "";
    public string Color { get; set; } = "";
    public int AvatarId { get; set; }
    public string? AuthProvider { get; set; } = "local";
}
