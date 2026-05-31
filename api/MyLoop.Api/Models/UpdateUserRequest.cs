namespace MyLoop.Api.Models;

public class UpdateUserRequest
{
    public string? DisplayName { get; set; }
    public string? Color { get; set; }
    public int? AvatarId { get; set; }
}
