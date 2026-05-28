/// <summary>
/// MyLoop API — Entry point for the territory-capture game backend.
/// Configures services, database, and HTTP pipeline for the minimal API.
/// </summary>

using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Endpoints;
using MyLoop.Api.Entities;

var builder = WebApplication.CreateBuilder(args);

// Register the EF Core DbContext with PostgreSQL as the backing store.
// Connection string is read from appsettings.json / environment variables.
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Enable CORS for the Flutter web frontend
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.WithOrigins(
            "http://localhost:9090",
            "http://192.168.1.8:9090",
            "http://localhost:5048"
        ).AllowAnyMethod().AllowAnyHeader());
});

var app = builder.Build();

app.UseCors();

// Ensure the database schema exists on startup.
// This is a dev convenience — in production, use EF Core migrations instead.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();

    // Seed data if the Users table is empty
    if (!db.Users.Any())
    {
        var users = new[]
        {
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_kai", DisplayName = "Kai", Color = "#60A5FA", AvatarId = 9, HexCount = 6200, Streak = 42, DistanceKm = 248.5, MaxStreak = 42, TopThreeFinishes = 38, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-120) },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_zoe", DisplayName = "Zoe", Color = "#00BCD4", AvatarId = 11, HexCount = 3100, Streak = 28, DistanceKm = 155.2, MaxStreak = 35, TopThreeFinishes = 22, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-95) },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_alex", DisplayName = "Alex", Color = "#00D4AA", AvatarId = 0, HexCount = 1450, Streak = 19, DistanceKm = 89.7, MaxStreak = 24, TopThreeFinishes = 11, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-80) },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_maya", DisplayName = "Maya", Color = "#8B5CF6", AvatarId = 3, HexCount = 820, Streak = 14, DistanceKm = 52.3, MaxStreak = 14, TopThreeFinishes = 5, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-60) },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_ravi", DisplayName = "Ravi", Color = "#FF9600", AvatarId = 5, HexCount = 560, Streak = 9, DistanceKm = 34.8, MaxStreak = 12, TopThreeFinishes = 2, IsStreakActive = false, CreatedAt = DateTime.UtcNow.AddDays(-45) },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_priya", DisplayName = "Priya", Color = "#FFD700", AvatarId = 8, HexCount = 210, Streak = 7, DistanceKm = 18.4, MaxStreak = 10, TopThreeFinishes = 0, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-30) },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_leo", DisplayName = "Leo", Color = "#A8B4C0", AvatarId = 4, HexCount = 130, Streak = 5, DistanceKm = 11.2, MaxStreak = 8, TopThreeFinishes = 0, IsStreakActive = false, CreatedAt = DateTime.UtcNow.AddDays(-20) },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_robin", DisplayName = "Robin", Color = "#00D4AA", AvatarId = 1, HexCount = 24, Streak = 5, DistanceKm = 4.8, MaxStreak = 5, TopThreeFinishes = 0, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-7) },
        };
        db.Users.AddRange(users);
        db.SaveChanges();

        // Create today's leaderboard entries
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var sorted = users.OrderByDescending(u => u.HexCount).ToList();
        for (int i = 0; i < sorted.Count; i++)
        {
            db.LeaderboardEntries.Add(new LeaderboardEntry
            {
                Id = Guid.NewGuid(),
                UserId = sorted[i].Id,
                Date = today,
                CellCount = sorted[i].HexCount,
                AreaM2 = sorted[i].HexCount * 15047.5, // ~15k m² per H3 res-8 cell
                Rank = i + 1,
            });
        }
        db.SaveChanges();
    }
}

// Health check endpoint — confirms the API process is alive and accepting requests
app.MapGet("/", () => "MyLoop API is running");

// Register all domain endpoint groups (Users, Territory/Claims, Leaderboard)
app.MapUserEndpoints();
app.MapTerritoryEndpoints();
app.MapLeaderboardEndpoints();

app.Run();
