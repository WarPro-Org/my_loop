using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;

namespace MyLoop.Api.Endpoints;

/// <summary>
/// User management endpoints — registration, profile retrieval, and profile updates.
/// Handles the lifecycle of a player account after Firebase authentication.
/// </summary>
public static class UserEndpoints
{
    /// <summary>
    /// Maps all user-related HTTP endpoints under the <c>/api/users</c> route group.
    /// </summary>
    /// <param name="app">The <see cref="WebApplication"/> to register routes on.</param>
    public static void MapUserEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/users");

        // POST /api/users/register
        // Register a new user. Called once after Firebase sign-in.
        // The app sends the Firebase UID + chosen display name, color, and avatar.
        group.MapPost("/register", async (
            [FromBody] RegisterRequest request,
            AppDbContext db) =>
        {
            // Input validation
            if (string.IsNullOrWhiteSpace(request.FirebaseUid) || request.FirebaseUid.Length > 128)
                return Results.BadRequest("Invalid FirebaseUid");
            if (string.IsNullOrWhiteSpace(request.DisplayName) || request.DisplayName.Length > 30)
                return Results.BadRequest("DisplayName must be 1-30 characters");
            if (string.IsNullOrWhiteSpace(request.Color) || !System.Text.RegularExpressions.Regex.IsMatch(request.Color, @"^#[0-9A-Fa-f]{6}$"))
                return Results.BadRequest("Color must be a valid hex color (e.g. #FF5733)");
            if (request.AvatarId < 0 || request.AvatarId > 50)
                return Results.BadRequest("AvatarId must be 0-50");

            // Prevent duplicate accounts — one Firebase UID maps to exactly one MyLoop user
            if (await db.Users.AnyAsync(u => u.FirebaseUid == request.FirebaseUid))
                return Results.Conflict("User already registered");

            var user = new User
            {
                Id = Guid.NewGuid(),
                FirebaseUid = request.FirebaseUid,
                DisplayName = request.DisplayName.Trim(),
                Color = request.Color,
                AvatarId = request.AvatarId
            };

            db.Users.Add(user);
            await db.SaveChangesAsync();
            return Results.Created($"/api/users/{user.Id}", user);
        });

        // GET /api/users/{id}
        // Get my profile. The app calls this on startup to load the user's info.
        group.MapGet("/{id:guid}", async (Guid id, AppDbContext db) =>
        {
            var user = await db.Users.FindAsync(id);
            return user is null ? Results.NotFound() : Results.Ok(user);
        });

        // GET /api/users/by-uid/{firebaseUid}
        // Lookup user by Firebase UID — used for login (returns user or 404 if not registered).
        group.MapGet("/by-uid/{firebaseUid}", async (string firebaseUid, AppDbContext db) =>
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);
            return user is null ? Results.NotFound() : Results.Ok(user);
        });

        // PATCH /api/users/{id}
        // Update avatar or color. User can change their look anytime.
        group.MapPatch("/{id:guid}", async (
            Guid id,
            [FromBody] UpdateUserRequest request,
            AppDbContext db) =>
        {
            var user = await db.Users.FindAsync(id);
            if (user is null) return Results.NotFound();

            // Only overwrite fields that were explicitly provided (non-null)
            if (request.DisplayName is not null) user.DisplayName = request.DisplayName;
            if (request.Color is not null) user.Color = request.Color;
            if (request.AvatarId is not null) user.AvatarId = request.AvatarId.Value;

            await db.SaveChangesAsync();
            return Results.Ok(user);
        });
        // GET /api/users/{id}/profile
        // Rich public profile with computed stats (rank, top 3 history, etc.)
        group.MapGet("/{id:guid}/profile", async (Guid id, AppDbContext db) =>
        {
            var user = await db.Users.FindAsync(id);
            if (user is null) return Results.NotFound();

            var today = DateOnly.FromDateTime(DateTime.UtcNow);

            // Get current rank from today's leaderboard
            var entry = await db.LeaderboardEntries
                .Where(l => l.Date == today && l.UserId == id)
                .FirstOrDefaultAsync();
            var currentRank = entry?.Rank ?? 0;

            // Count total players (for "out of X" display)
            var totalPlayers = await db.LeaderboardEntries
                .Where(l => l.Date == today)
                .CountAsync();

            return Results.Ok(new
            {
                user.Id,
                user.DisplayName,
                user.Color,
                user.AvatarId,
                user.HexCount,
                user.Streak,
                user.MaxStreak,
                user.DistanceKm,
                user.TopThreeFinishes,
                user.IsStreakActive,
                JoinedAt = user.CreatedAt,
                CurrentRank = currentRank,
                TotalPlayers = totalPlayers,
            });
        });
    }

    /// <summary>
    /// Request body for registering a new user after Firebase authentication.
    /// </summary>
    /// <param name="FirebaseUid">The unique identifier from Firebase Auth.</param>
    /// <param name="DisplayName">The player's chosen display name.</param>
    /// <param name="Color">Hex color string (e.g., "#FF5733") used to render the player's territory.</param>
    /// <param name="AvatarId">Index of the selected avatar graphic.</param>
    public record RegisterRequest(string FirebaseUid, string DisplayName, string Color, int AvatarId);

    /// <summary>
    /// Request body for updating a user's profile. All fields are optional —
    /// only non-null values will be applied.
    /// </summary>
    /// <param name="DisplayName">New display name, or null to keep current.</param>
    /// <param name="Color">New hex color, or null to keep current.</param>
    /// <param name="AvatarId">New avatar index, or null to keep current.</param>
    public record UpdateUserRequest(string? DisplayName, string? Color, int? AvatarId);
}
