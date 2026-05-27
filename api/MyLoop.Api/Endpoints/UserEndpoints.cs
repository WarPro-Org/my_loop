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
            // Prevent duplicate accounts — one Firebase UID maps to exactly one MyLoop user
            if (await db.Users.AnyAsync(u => u.FirebaseUid == request.FirebaseUid))
                return Results.Conflict("User already registered");

            var user = new User
            {
                Id = Guid.NewGuid(),
                FirebaseUid = request.FirebaseUid,
                DisplayName = request.DisplayName,
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
