using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.DTOs;
using MyLoop.Api.Entities;
using MyLoop.Api.Services;

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
        // Register a new user. Called once after sign-in (federated or local).
        // For local accounts, FirebaseUid can be "local_<name>" or empty — a unique one is generated.
        group.MapPost("/register", async (
            [FromBody] RegisterRequest request,
            AppDbContext db) =>
        {
            // Input validation
            var nameError = ValidationService.ValidateDisplayName(request.DisplayName);
            if (nameError != null) return Results.BadRequest(nameError);
            var colorError = ValidationService.ValidateColor(request.Color);
            if (colorError != null) return Results.BadRequest(colorError);
            var avatarError = ValidationService.ValidateAvatarId(request.AvatarId);
            if (avatarError != null) return Results.BadRequest(avatarError);

            var authProvider = request.AuthProvider ?? "local";
            var firebaseUid = request.FirebaseUid;

            // For local accounts, generate a unique UID if not provided or starts with "dev_"/"local_"
            if (string.IsNullOrWhiteSpace(firebaseUid) || firebaseUid.StartsWith("dev_") || firebaseUid.StartsWith("local_"))
            {
                firebaseUid = $"local_{Guid.NewGuid():N}";
                authProvider = "local";
            }

            // Check if user already exists — return existing user (graceful re-registration)
            var existing = await db.Users.FirstOrDefaultAsync(u => u.FirebaseUid == firebaseUid);
            if (existing is not null)
                return Results.Ok(existing);

            var user = new User
            {
                Id = Guid.NewGuid(),
                FirebaseUid = firebaseUid,
                DisplayName = request.DisplayName.Trim(),
                Color = request.Color,
                AvatarId = request.AvatarId,
                AuthProvider = authProvider,
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

            // Validate inputs to prevent injection and bad data
            if (request.DisplayName is not null)
            {
                var nameError = ValidationService.ValidateDisplayName(request.DisplayName);
                if (nameError != null) return Results.BadRequest(nameError);
                user.DisplayName = request.DisplayName.Trim();
            }
            if (request.Color is not null)
            {
                var colorError = ValidationService.ValidateColor(request.Color);
                if (colorError != null) return Results.BadRequest(colorError);
                user.Color = request.Color;
            }
            if (request.AvatarId is not null)
            {
                var avatarError = ValidationService.ValidateAvatarId(request.AvatarId.Value);
                if (avatarError != null) return Results.BadRequest(avatarError);
                user.AvatarId = request.AvatarId.Value;
            }

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
}
