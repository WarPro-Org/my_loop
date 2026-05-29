namespace MyLoop.Api.DTOs;

/// <summary>Request body for user registration.</summary>
public record RegisterRequest(
    string? FirebaseUid,
    string DisplayName,
    string Color,
    int AvatarId,
    string? AuthProvider = "local"
);

/// <summary>Request body for updating a user's profile. Only non-null fields are applied.</summary>
public record UpdateUserRequest(string? DisplayName, string? Color, int? AvatarId);

/// <summary>Request body for submitting a territory claim.</summary>
public record ClaimRequest(Guid UserId, double[][] Path);
