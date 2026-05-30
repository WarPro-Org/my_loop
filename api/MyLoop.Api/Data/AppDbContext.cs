using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Entities;

namespace MyLoop.Api.Data;

/// <summary>
/// Entity Framework Core database context for the MyLoop application.
/// Manages all entity sets and configures the relational model (indexes, keys, constraints).
/// Backed by PostgreSQL via Npgsql.
/// </summary>
public class AppDbContext : DbContext
{
    /// <summary>
    /// Initializes a new instance of <see cref="AppDbContext"/> with the specified options.
    /// </summary>
    /// <param name="options">The database context configuration options (connection string, provider, etc.).</param>
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    /// <summary>Gets the set of registered players.</summary>
    public DbSet<User> Users => Set<User>();

    /// <summary>Gets the set of completed territory claims (loop submissions).</summary>
    public DbSet<Claim> Claims => Set<Claim>();

    /// <summary>Gets the set of individual hex cells that make up the territory map.</summary>
    public DbSet<TerritoryCell> TerritoryCells => Set<TerritoryCell>();

    /// <summary>Gets the set of ownership transfer events (cell ownership history).</summary>
    public DbSet<CellTransfer> CellTransfers => Set<CellTransfer>();

    /// <summary>Gets the set of daily leaderboard snapshots.</summary>
    public DbSet<LeaderboardEntry> LeaderboardEntries => Set<LeaderboardEntry>();

    /// <summary>
    /// Configures the entity model: primary keys, unique constraints, and indexes
    /// for efficient query patterns used by the game.
    /// </summary>
    /// <param name="modelBuilder">The builder used to construct the EF Core model.</param>
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
            e.HasIndex(t => new { t.CenterLat, t.CenterLng }); // viewport queries (will upgrade to point+GiST via raw SQL)
            e.HasIndex(t => t.ParentCellId); // geohash-style partition pruning by area
        });

        // CellTransfer: ownership history for revenge/recapture features
        modelBuilder.Entity<CellTransfer>(e =>
        {
            e.HasIndex(t => new { t.FromUserId, t.TransferredAt }); // "hexes stolen from me, most recent first"
            e.HasIndex(t => new { t.ToUserId, t.TransferredAt }); // "hexes I've captured"
            e.HasIndex(t => t.CellId); // "full history of this hex"
        });

        // LeaderboardEntry: one entry per user per day
        modelBuilder.Entity<LeaderboardEntry>(e =>
        {
            e.HasIndex(l => new { l.Date, l.Rank }); // fast lookup: "top N on this date"
            e.HasIndex(l => new { l.UserId, l.Date }).IsUnique(); // prevent duplicate entries per user/day
        });
    }
}
