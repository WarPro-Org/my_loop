using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Endpoints;

var builder = WebApplication.CreateBuilder(args);

// Connect to PostgreSQL
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

var app = builder.Build();

// Create database tables on startup (replace with migrations later)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();
}

// Health check — just confirms the API is alive
app.MapGet("/", () => "MyLoop API is running");

// Register all endpoints
app.MapUserEndpoints();
app.MapTerritoryEndpoints();
app.MapLeaderboardEndpoints();

app.Run();
