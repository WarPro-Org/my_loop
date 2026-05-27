using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Entities;

namespace MyLoop.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Claim> Claims => Set<Claim>();
    public DbSet<TerritoryCell> TerritoryCells => Set<TerritoryCell>();
    public DbSet<LeaderboardEntry> LeaderboardEntries => Set<LeaderboardEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // User: firebase UID must be unique (no duplicate accounts)
        modelBuilder.Entity<User>(e =>
        {
            e.HasIndex(u => u.FirebaseUid).IsUnique();
        });

        // TerritoryCell: the H3 cell ID is the primary key (one owner per hex)
        modelBuilder.Entity<TerritoryCell>(e =>
        {
            e.HasKey(t => t.CellId);
            e.HasIndex(t => t.OwnerId); // fast lookup: "give me all cells owned by this user"
        });

        // LeaderboardEntry: one entry per user per day
        modelBuilder.Entity<LeaderboardEntry>(e =>
        {
            e.HasIndex(l => new { l.Date, l.Rank }); // fast lookup: "top N on this date"
            e.HasIndex(l => new { l.UserId, l.Date }).IsUnique();
        });
    }
}
