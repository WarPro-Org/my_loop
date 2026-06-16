using MyLoop.Api.Entities;

namespace MyLoop.Api.Data.Seeding;

/// <summary>
/// Bootstrap user roster used only when the database is empty, so a fresh install has a populated
/// map and leaderboard on day one. Data-only — no behavior.
/// </summary>
public static class SeedUsers
{
    public static User[] Build() =>
    [
        // === Bangalore, India ===
        Make("uid_kai", "Kai", "#60A5FA", 9, 6200, 42, 248.5, 42, 38, true, -120, "Bangalore", "India"),
        Make("uid_zoe", "Zoe", "#00BCD4", 11, 3100, 28, 155.2, 35, 22, true, -95, "Bangalore", "India"),
        Make("uid_alex", "Alex", "#00D4AA", 0, 1450, 19, 89.7, 24, 11, true, -80, "Bangalore", "India"),
        Make("uid_maya", "Maya", "#8B5CF6", 3, 820, 14, 52.3, 14, 5, true, -60, "Bangalore", "India"),
        Make("uid_ravi", "Ravi", "#FF9600", 5, 560, 9, 34.8, 12, 2, false, -45, "Bangalore", "India"),
        Make("uid_priya", "Priya", "#FFD700", 8, 210, 7, 18.4, 10, 0, true, -30, "Bangalore", "India"),
        Make("uid_leo", "Leo", "#A8B4C0", 4, 130, 5, 11.2, 8, 0, false, -20, "Bangalore", "India"),
        Make("uid_robin", "Robin", "#00D4AA", 1, 24, 5, 4.8, 5, 0, true, -7, "Bangalore", "India"),
        Make("uid_arjun", "Arjun", "#FF6B81", 2, 980, 11, 62.1, 18, 4, true, -55, "Bangalore", "India"),
        Make("uid_nisha", "Nisha", "#A560E8", 7, 445, 8, 28.9, 11, 1, true, -40, "Bangalore", "India"),
        Make("uid_vikram", "Vikram", "#1CB0F6", 10, 1850, 22, 112.4, 22, 14, true, -88, "Bangalore", "India"),
        Make("uid_deepa", "Deepa", "#FFC800", 6, 310, 6, 22.7, 9, 0, false, -35, "Bangalore", "India"),

        // === Mumbai, India ===
        Make("uid_aisha", "Aisha", "#FF4B4B", 12, 4800, 35, 195.3, 35, 28, true, -110, "Mumbai", "India"),
        Make("uid_rohit", "Rohit", "#00D4AA", 14, 2700, 25, 138.6, 30, 18, true, -90, "Mumbai", "India"),
        Make("uid_meera", "Meera", "#8B5CF6", 15, 1200, 16, 76.2, 20, 8, true, -70, "Mumbai", "India"),
        Make("uid_sahil", "Sahil", "#FF9600", 13, 680, 10, 42.1, 13, 3, false, -50, "Mumbai", "India"),
        Make("uid_tanya", "Tanya", "#FF6B81", 16, 390, 7, 25.4, 9, 1, true, -38, "Mumbai", "India"),
        Make("uid_dev", "Dev", "#60A5FA", 17, 150, 4, 12.8, 7, 0, true, -22, "Mumbai", "India"),

        // === Delhi, India ===
        Make("uid_kabir", "Kabir", "#FFC800", 18, 2200, 20, 125.8, 26, 15, true, -85, "Delhi", "India"),
        Make("uid_ananya", "Ananya", "#00BCD4", 19, 1100, 15, 68.5, 18, 6, true, -65, "Delhi", "India"),
        Make("uid_raj", "Raj", "#A560E8", 20, 520, 8, 33.2, 11, 2, false, -42, "Delhi", "India"),

        // === London, UK ===
        Make("uid_emma", "Emma", "#FF4B4B", 21, 5500, 38, 220.1, 38, 32, true, -115, "London", "United Kingdom"),
        Make("uid_james", "James", "#1CB0F6", 22, 3400, 30, 168.9, 33, 24, true, -100, "London", "United Kingdom"),
        Make("uid_olivia", "Olivia", "#8B5CF6", 23, 1600, 18, 95.4, 21, 9, true, -75, "London", "United Kingdom"),
        Make("uid_harry", "Harry", "#FF9600", 24, 740, 11, 46.7, 15, 3, true, -52, "London", "United Kingdom"),

        // === New York, USA ===
        Make("uid_mike", "Mike", "#00D4AA", 25, 7100, 45, 285.3, 45, 42, true, -130, "New York", "United States"),
        Make("uid_sarah", "Sarah", "#FF6B81", 26, 4200, 33, 178.6, 36, 26, true, -105, "New York", "United States"),
        Make("uid_chris", "Chris", "#FFC800", 27, 2400, 21, 132.1, 28, 16, true, -82, "New York", "United States"),
        Make("uid_jessica", "Jessica", "#A560E8", 28, 920, 12, 58.4, 16, 4, true, -48, "New York", "United States"),

        // === Tokyo, Japan ===
        Make("uid_yuki", "Yuki", "#00BCD4", 29, 5800, 40, 232.7, 40, 35, true, -118, "Tokyo", "Japan"),
        Make("uid_hiro", "Hiro", "#FF4B4B", 30, 3800, 32, 162.3, 34, 20, true, -98, "Tokyo", "Japan"),
    ];

    private static User Make(
        string firebaseUid, string displayName, string color, int avatarId, int hexCount, int streak,
        double distanceKm, int maxStreak, int topThreeFinishes, bool isStreakActive, int createdDaysAgo,
        string city, string country) => new()
    {
        Id = Guid.NewGuid(),
        FirebaseUid = firebaseUid,
        DisplayName = displayName,
        Color = color,
        AvatarId = avatarId,
        HexCount = hexCount,
        Streak = streak,
        DistanceKm = distanceKm,
        MaxStreak = maxStreak,
        TopThreeFinishes = topThreeFinishes,
        IsStreakActive = isStreakActive,
        CreatedAt = DateTime.UtcNow.AddDays(createdDaysAgo),
        City = city,
        Country = country,
    };
}
