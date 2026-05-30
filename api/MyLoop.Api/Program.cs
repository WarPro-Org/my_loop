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
        policy.WithOrigins(
            "http://localhost:9090",
            "http://192.168.1.8:9090",
            "http://localhost:5048"
        ).AllowAnyMethod().AllowAnyHeader());
});

var app = builder.Build();

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// Ensure the database schema exists on startup.
// This is a dev convenience — in production, use EF Core migrations instead.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();

    // Add AuthProvider column if missing (handles existing DBs without recreating)
    try
    {
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"AuthProvider\" text NOT NULL DEFAULT 'local'");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"TopTenFinishes\" integer NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"TopHundredFinishes\" integer NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"TopThousandFinishes\" integer NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"Users\" ADD COLUMN IF NOT EXISTS \"LastClaimDate\" date");
    }
    catch { /* Column already exists or DB was just created with it */ }

    // Add territory ownership history columns and table (handles existing DBs)
    try
    {
        // New columns on TerritoryCells for spatial queries
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"CenterLat\" double precision NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"CenterLng\" double precision NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"ParentCellId\" bigint NOT NULL DEFAULT 0");
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" ADD COLUMN IF NOT EXISTS \"CooldownExpiresAt\" timestamp with time zone");

        // Drop PreviousOwnerId if it exists (replaced by CellTransfers table)
        db.Database.ExecuteSqlRaw(
            "ALTER TABLE \"TerritoryCells\" DROP COLUMN IF EXISTS \"PreviousOwnerId\"");

        // CellTransfers table — ownership history for revenge recapture feature
        db.Database.ExecuteSqlRaw(@"
            CREATE TABLE IF NOT EXISTS ""CellTransfers"" (
                ""Id"" uuid PRIMARY KEY,
                ""CellId"" bigint NOT NULL,
                ""FromUserId"" uuid NULL,
                ""ToUserId"" uuid NOT NULL,
                ""ClaimId"" uuid NOT NULL,
                ""TransferredAt"" timestamp with time zone NOT NULL
            )");

        // Indexes for CellTransfers (idempotent with IF NOT EXISTS)
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_CellTransfers_FromUserId_TransferredAt""
            ON ""CellTransfers"" (""FromUserId"", ""TransferredAt"" DESC)");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_CellTransfers_ToUserId_TransferredAt""
            ON ""CellTransfers"" (""ToUserId"", ""TransferredAt"" DESC)");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_CellTransfers_CellId""
            ON ""CellTransfers"" (""CellId"")");

        // Indexes for TerritoryCells columns
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_CenterLatLng""
            ON ""TerritoryCells"" (""CenterLat"", ""CenterLng"")");
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_ParentCellId""
            ON ""TerritoryCells"" (""ParentCellId"")");

        // True 2D spatial index using PostgreSQL native point + GiST
        // This uses an expression index: point(CenterLng, CenterLat) — note: PG point is (x, y) = (lng, lat)
        db.Database.ExecuteSqlRaw(@"
            CREATE INDEX IF NOT EXISTS ""IX_TerritoryCells_Center_GiST""
            ON ""TerritoryCells"" USING gist (point(""CenterLng"", ""CenterLat""))");
    }
    catch { /* Tables/columns already exist or DB was just created with them */ }

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
