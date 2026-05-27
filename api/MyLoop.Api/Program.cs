/// <summary>
/// MyLoop API — Entry point for the territory-capture game backend.
/// Configures services, database, and HTTP pipeline for the minimal API.
/// </summary>

using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Endpoints;

var builder = WebApplication.CreateBuilder(args);

// Register the EF Core DbContext with PostgreSQL as the backing store.
// Connection string is read from appsettings.json / environment variables.
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

var app = builder.Build();

// Ensure the database schema exists on startup.
// This is a dev convenience — in production, use EF Core migrations instead.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();
}

// Health check endpoint — confirms the API process is alive and accepting requests
app.MapGet("/", () => "MyLoop API is running");

// Register all domain endpoint groups (Users, Territory/Claims, Leaderboard)
app.MapUserEndpoints();
app.MapTerritoryEndpoints();
app.MapLeaderboardEndpoints();

app.Run();
