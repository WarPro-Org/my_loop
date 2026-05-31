namespace MyLoop.Api.Models;

public class DeviceTokenRequest
{
    public required string Token { get; set; }
    public string? Platform { get; set; }
}
