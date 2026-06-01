namespace MyLoop.Api.Models;

/// <summary>
/// Full geographic location info from reverse geocoding.
/// Used for decay tier calculation (same city / state / country / continent).
/// </summary>
public class LocationInfo
{
    public string City { get; set; } = "";
    public string State { get; set; } = "";
    public string Country { get; set; } = "";
    public string CountryCode { get; set; } = "";
    public string Continent { get; set; } = "";

    public bool IsEmpty => string.IsNullOrEmpty(City) && string.IsNullOrEmpty(Country);
}
