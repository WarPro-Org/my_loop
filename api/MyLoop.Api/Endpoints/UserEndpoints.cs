using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;

namespace MyLoop.Api.Endpoints;

/// Everything about users — register, get profile, update avatar/color.
public static class UserEndpoints
{
    public static void MapUserEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/users");

        // Register a new user. Called once after Firebase sign-in.
        // The app sends the Firebase UID + chosen display name, color, and avatar.
        group.MapPost("/register", async (
            [FromBody] RegisterRequest request,
            AppDbContext db) =>
        {
            // Don't allow duplicate accounts for the same Firebase user
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

        // Get my profile. The app calls this on startup to load the user's info.
        group.MapGet("/{id:guid}", async (Guid id, AppDbContext db) =>
        {
            var user = await db.Users.FindAsync(id);
            return user is null ? Results.NotFound() : Results.Ok(user);
        });

        // Update avatar or color. User can change their look anytime.
        group.MapPatch("/{id:guid}", async (
            Guid id,
            [FromBody] UpdateUserRequest request,
            AppDbContext db) =>
        {
            var user = await db.Users.FindAsync(id);
            if (user is null) return Results.NotFound();

            if (request.DisplayName is not null) user.DisplayName = request.DisplayName;
            if (request.Color is not null) user.Color = request.Color;
            if (request.AvatarId is not null) user.AvatarId = request.AvatarId.Value;

            await db.SaveChangesAsync();
            return Results.Ok(user);
        });
    }

    public record RegisterRequest(string FirebaseUid, string DisplayName, string Color, int AvatarId);
    public record UpdateUserRequest(string? DisplayName, string? Color, int? AvatarId);
}
