using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// --- Database ---
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// --- Dependency Injection: register all services ---
builder.Services.AddScoped<IValidationService, ValidationService>();
builder.Services.AddScoped<IGeoService, GeoService>();
builder.Services.AddScoped<IHexGridService, HexGridService>();
builder.Services.AddScoped<ITerritoryService, TerritoryService>();
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<ILeaderboardService, LeaderboardService>();
builder.Services.AddScoped<ITerritoryNotifier, TerritoryNotifier>();
builder.Services.AddScoped<IPathValidationService, PathValidationService>();
builder.Services.AddScoped<IPushNotificationService, PushNotificationService>();
builder.Services.AddHostedService<DecayCleanupService>();

// --- SignalR ---
builder.Services.AddSignalR();

// --- Controllers ---
builder.Services.AddControllers();

// --- Firebase JWT Authentication ---
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://securetoken.google.com/myloop-6aefc";
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = "https://securetoken.google.com/myloop-6aefc",
            ValidateAudience = true,
            ValidAudience = "myloop-6aefc",
            ValidateLifetime = true,
        };
    });
builder.Services.AddAuthorization();

// --- CORS ---
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.SetIsOriginAllowed(_ => true)
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials());
});

var app = builder.Build();

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHub<MyLoop.Api.Hubs.TerritoryHub>("/hubs/territory");

// Privacy Policy & Terms — required by Apple App Store (Guideline 5.1.1)
app.MapGet("/privacy", () => Results.Content("""
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MyLoop — Privacy Policy</title>
<style>body{font-family:system-ui,sans-serif;max-width:700px;margin:2rem auto;padding:0 1rem;line-height:1.6;color:#222}h1{font-size:1.5rem}h2{font-size:1.1rem;margin-top:2rem}</style>
</head><body>
<h1>Privacy Policy</h1>
<p><strong>Last updated:</strong> May 31, 2026</p>
<p>MyLoop ("we", "our", "the app") is a territory-capture walking game. This policy explains what data we collect and how we use it.</p>
<h2>1. Data We Collect</h2>
<ul>
<li><strong>Account info:</strong> Display name, avatar selection, chosen color. If you sign in with Google or Apple, we receive your email and name from the provider.</li>
<li><strong>Location data:</strong> GPS coordinates while you actively record a journey. We do NOT track your location when you are not on an active walk.</li>
<li><strong>Game data:</strong> Territory cells claimed, walk paths, leaderboard statistics, streaks.</li>
</ul>
<h2>2. How We Use Your Data</h2>
<ul>
<li>To operate the game: claim territory, compute leaderboards, display your hexes on the map.</li>
<li>To show other players' territory on your map (anonymized by color, not personal info).</li>
<li>We do NOT sell your data. We do NOT run ads. We do NOT share data with third parties beyond Firebase Authentication.</li>
</ul>
<h2>3. Data Retention</h2>
<p>Your data is stored as long as your account is active. You can delete your account at any time from the app's profile menu. Deletion removes all your data permanently within 24 hours.</p>
<h2>4. Location Permission</h2>
<p>The app requests "Always" location access so your walk continues tracking if you briefly switch apps. You can choose "While Using" instead — walks will only record when the app is in the foreground.</p>
<h2>5. Children</h2>
<p>MyLoop is not directed at children under 13. We do not knowingly collect data from minors.</p>
<h2>6. Contact</h2>
<p>Questions? Email us at <a href="mailto:support@myloop.app">support@myloop.app</a></p>
</body></html>
""", "text/html"));

app.MapGet("/terms", () => Results.Content("""
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MyLoop — Terms of Service</title>
<style>body{font-family:system-ui,sans-serif;max-width:700px;margin:2rem auto;padding:0 1rem;line-height:1.6;color:#222}h1{font-size:1.5rem}h2{font-size:1.1rem;margin-top:2rem}</style>
</head><body>
<h1>Terms of Service</h1>
<p><strong>Last updated:</strong> May 31, 2026</p>
<p>By using MyLoop you agree to these terms.</p>
<h2>1. Fair Play</h2>
<p>GPS spoofing, automation, or any form of cheating will result in permanent account suspension.</p>
<h2>2. Content</h2>
<p>Display names must not contain offensive, hateful, or inappropriate language. We reserve the right to force-rename or ban violating accounts.</p>
<h2>3. Availability</h2>
<p>The service is provided "as is". We may modify or discontinue features at any time.</p>
<h2>4. Account Termination</h2>
<p>You may delete your account at any time. We may suspend accounts that violate these terms.</p>
<h2>5. Liability</h2>
<p>Play safely. Do not trespass or enter dangerous areas to capture territory. MyLoop is not responsible for injuries sustained while using the app.</p>
</body></html>
""", "text/html"));

// Ensure the database schema exists on startup.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();

    // Apply new columns/tables added in the decay + exploration feature.
    // EnsureCreated won't add these to an existing DB — run idempotent ALTER/CREATE.
    try
    {
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"LastRefreshedAt\" timestamp with time zone NOT NULL DEFAULT NOW()");
        db.Database.ExecuteSqlRaw(@"
            CREATE TABLE IF NOT EXISTS ""ExploredCells"" (
                ""UserId"" uuid NOT NULL,
                ""CellId"" bigint NOT NULL,
                ""NeighborhoodId"" bigint NOT NULL,
                ""FirstVisitedAt"" timestamp with time zone NOT NULL,
                CONSTRAINT ""PK_ExploredCells"" PRIMARY KEY (""UserId"", ""CellId"")
            )");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_ExploredCells_UserId_NeighborhoodId""
            ON ""ExploredCells"" (""UserId"", ""NeighborhoodId"")");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_ExploredCells_NeighborhoodId""
            ON ""ExploredCells"" (""NeighborhoodId"")");
    }
    catch { /* Column/table already exists */ }

    // Seed data if the Users table is empty
    if (!db.Users.Any())
    {
        var users = new[]
        {
            // === Bangalore, India ===
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_kai", DisplayName = "Kai", Color = "#60A5FA", AvatarId = 9, HexCount = 6200, Streak = 42, DistanceKm = 248.5, MaxStreak = 42, TopThreeFinishes = 38, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-120), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_zoe", DisplayName = "Zoe", Color = "#00BCD4", AvatarId = 11, HexCount = 3100, Streak = 28, DistanceKm = 155.2, MaxStreak = 35, TopThreeFinishes = 22, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-95), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_alex", DisplayName = "Alex", Color = "#00D4AA", AvatarId = 0, HexCount = 1450, Streak = 19, DistanceKm = 89.7, MaxStreak = 24, TopThreeFinishes = 11, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-80), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_maya", DisplayName = "Maya", Color = "#8B5CF6", AvatarId = 3, HexCount = 820, Streak = 14, DistanceKm = 52.3, MaxStreak = 14, TopThreeFinishes = 5, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-60), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_ravi", DisplayName = "Ravi", Color = "#FF9600", AvatarId = 5, HexCount = 560, Streak = 9, DistanceKm = 34.8, MaxStreak = 12, TopThreeFinishes = 2, IsStreakActive = false, CreatedAt = DateTime.UtcNow.AddDays(-45), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_priya", DisplayName = "Priya", Color = "#FFD700", AvatarId = 8, HexCount = 210, Streak = 7, DistanceKm = 18.4, MaxStreak = 10, TopThreeFinishes = 0, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-30), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_leo", DisplayName = "Leo", Color = "#A8B4C0", AvatarId = 4, HexCount = 130, Streak = 5, DistanceKm = 11.2, MaxStreak = 8, TopThreeFinishes = 0, IsStreakActive = false, CreatedAt = DateTime.UtcNow.AddDays(-20), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_robin", DisplayName = "Robin", Color = "#00D4AA", AvatarId = 1, HexCount = 24, Streak = 5, DistanceKm = 4.8, MaxStreak = 5, TopThreeFinishes = 0, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-7), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_arjun", DisplayName = "Arjun", Color = "#FF6B81", AvatarId = 2, HexCount = 980, Streak = 11, DistanceKm = 62.1, MaxStreak = 18, TopThreeFinishes = 4, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-55), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_nisha", DisplayName = "Nisha", Color = "#A560E8", AvatarId = 7, HexCount = 445, Streak = 8, DistanceKm = 28.9, MaxStreak = 11, TopThreeFinishes = 1, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-40), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_vikram", DisplayName = "Vikram", Color = "#1CB0F6", AvatarId = 10, HexCount = 1850, Streak = 22, DistanceKm = 112.4, MaxStreak = 22, TopThreeFinishes = 14, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-88), City = "Bangalore", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_deepa", DisplayName = "Deepa", Color = "#FFC800", AvatarId = 6, HexCount = 310, Streak = 6, DistanceKm = 22.7, MaxStreak = 9, TopThreeFinishes = 0, IsStreakActive = false, CreatedAt = DateTime.UtcNow.AddDays(-35), City = "Bangalore", Country = "India" },

            // === Mumbai, India ===
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_aisha", DisplayName = "Aisha", Color = "#FF4B4B", AvatarId = 12, HexCount = 4800, Streak = 35, DistanceKm = 195.3, MaxStreak = 35, TopThreeFinishes = 28, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-110), City = "Mumbai", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_rohit", DisplayName = "Rohit", Color = "#00D4AA", AvatarId = 14, HexCount = 2700, Streak = 25, DistanceKm = 138.6, MaxStreak = 30, TopThreeFinishes = 18, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-90), City = "Mumbai", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_meera", DisplayName = "Meera", Color = "#8B5CF6", AvatarId = 15, HexCount = 1200, Streak = 16, DistanceKm = 76.2, MaxStreak = 20, TopThreeFinishes = 8, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-70), City = "Mumbai", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_sahil", DisplayName = "Sahil", Color = "#FF9600", AvatarId = 13, HexCount = 680, Streak = 10, DistanceKm = 42.1, MaxStreak = 13, TopThreeFinishes = 3, IsStreakActive = false, CreatedAt = DateTime.UtcNow.AddDays(-50), City = "Mumbai", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_tanya", DisplayName = "Tanya", Color = "#FF6B81", AvatarId = 16, HexCount = 390, Streak = 7, DistanceKm = 25.4, MaxStreak = 9, TopThreeFinishes = 1, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-38), City = "Mumbai", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_dev", DisplayName = "Dev", Color = "#60A5FA", AvatarId = 17, HexCount = 150, Streak = 4, DistanceKm = 12.8, MaxStreak = 7, TopThreeFinishes = 0, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-22), City = "Mumbai", Country = "India" },

            // === Delhi, India ===
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_kabir", DisplayName = "Kabir", Color = "#FFC800", AvatarId = 18, HexCount = 2200, Streak = 20, DistanceKm = 125.8, MaxStreak = 26, TopThreeFinishes = 15, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-85), City = "Delhi", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_ananya", DisplayName = "Ananya", Color = "#00BCD4", AvatarId = 19, HexCount = 1100, Streak = 15, DistanceKm = 68.5, MaxStreak = 18, TopThreeFinishes = 6, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-65), City = "Delhi", Country = "India" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_raj", DisplayName = "Raj", Color = "#A560E8", AvatarId = 20, HexCount = 520, Streak = 8, DistanceKm = 33.2, MaxStreak = 11, TopThreeFinishes = 2, IsStreakActive = false, CreatedAt = DateTime.UtcNow.AddDays(-42), City = "Delhi", Country = "India" },

            // === London, UK ===
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_emma", DisplayName = "Emma", Color = "#FF4B4B", AvatarId = 21, HexCount = 5500, Streak = 38, DistanceKm = 220.1, MaxStreak = 38, TopThreeFinishes = 32, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-115), City = "London", Country = "United Kingdom" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_james", DisplayName = "James", Color = "#1CB0F6", AvatarId = 22, HexCount = 3400, Streak = 30, DistanceKm = 168.9, MaxStreak = 33, TopThreeFinishes = 24, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-100), City = "London", Country = "United Kingdom" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_olivia", DisplayName = "Olivia", Color = "#8B5CF6", AvatarId = 23, HexCount = 1600, Streak = 18, DistanceKm = 95.4, MaxStreak = 21, TopThreeFinishes = 9, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-75), City = "London", Country = "United Kingdom" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_harry", DisplayName = "Harry", Color = "#FF9600", AvatarId = 24, HexCount = 740, Streak = 11, DistanceKm = 46.7, MaxStreak = 15, TopThreeFinishes = 3, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-52), City = "London", Country = "United Kingdom" },

            // === New York, USA ===
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_mike", DisplayName = "Mike", Color = "#00D4AA", AvatarId = 25, HexCount = 7100, Streak = 45, DistanceKm = 285.3, MaxStreak = 45, TopThreeFinishes = 42, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-130), City = "New York", Country = "United States" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_sarah", DisplayName = "Sarah", Color = "#FF6B81", AvatarId = 26, HexCount = 4200, Streak = 33, DistanceKm = 178.6, MaxStreak = 36, TopThreeFinishes = 26, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-105), City = "New York", Country = "United States" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_chris", DisplayName = "Chris", Color = "#FFC800", AvatarId = 27, HexCount = 2400, Streak = 21, DistanceKm = 132.1, MaxStreak = 28, TopThreeFinishes = 16, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-82), City = "New York", Country = "United States" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_jessica", DisplayName = "Jessica", Color = "#A560E8", AvatarId = 28, HexCount = 920, Streak = 12, DistanceKm = 58.4, MaxStreak = 16, TopThreeFinishes = 4, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-48), City = "New York", Country = "United States" },

            // === Tokyo, Japan ===
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_yuki", DisplayName = "Yuki", Color = "#00BCD4", AvatarId = 29, HexCount = 5800, Streak = 40, DistanceKm = 232.7, MaxStreak = 40, TopThreeFinishes = 35, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-118), City = "Tokyo", Country = "Japan" },
            new User { Id = Guid.NewGuid(), FirebaseUid = "uid_hiro", DisplayName = "Hiro", Color = "#FF4B4B", AvatarId = 30, HexCount = 3800, Streak = 32, DistanceKm = 162.3, MaxStreak = 34, TopThreeFinishes = 20, IsStreakActive = true, CreatedAt = DateTime.UtcNow.AddDays(-98), City = "Tokyo", Country = "Japan" },
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
                AreaM2 = sorted[i].HexCount * GameConstants.CellAreaSquareMeters, // ~15k m² per H3 res-10 cell
                Rank = i + 1,
            });
        }
        db.SaveChanges();

        // Seed territory hexes for bot users so the map isn't empty on day 1
        TerritorySeedService.SeedBotTerritory(db, users.ToList());
    }
}

// Health check endpoint
app.MapGet("/", () => "MyLoop API is running");

// Auto-refresh leaderboard on startup so it's always current
using (var startupScope = app.Services.CreateScope())
{
    var leaderboardService = startupScope.ServiceProvider.GetRequiredService<ILeaderboardService>();
    var startupDb = startupScope.ServiceProvider.GetRequiredService<AppDbContext>();
    var today = DateOnly.FromDateTime(DateTime.UtcNow);
    var hasToday = startupDb.LeaderboardEntries.Any(l => l.Date == today);
    if (!hasToday)
    {
        // Generate today's leaderboard from user hex counts
        var ranked = startupDb.Users
            .OrderByDescending(u => u.HexCount)
            .Where(u => u.HexCount > 0)
            .ToList();
        for (int i = 0; i < ranked.Count; i++)
        {
            startupDb.LeaderboardEntries.Add(new LeaderboardEntry
            {
                Id = Guid.NewGuid(),
                UserId = ranked[i].Id,
                Date = today,
                CellCount = ranked[i].HexCount,
                AreaM2 = ranked[i].HexCount * GameConstants.CellAreaSquareMeters,
                Rank = i + 1,
            });
        }
        startupDb.SaveChanges();
    }
}

app.Run();
