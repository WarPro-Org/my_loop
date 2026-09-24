using Microsoft.AspNetCore.Authorization;
using MyLoop.Api.Interfaces;

namespace MyLoop.Api.Services.Moderation;

/// <summary>Requirement behind the <c>Moderator</c> policy.</summary>
public sealed class ModeratorRequirement : IAuthorizationRequirement;

/// <summary>
/// Grants the <c>Moderator</c> policy when the caller's Firebase UID (resolved by
/// <see cref="ICurrentUser"/>, the single identity source) is on the moderator allowlist.
/// </summary>
public sealed class ModeratorAuthorizationHandler(ICurrentUser currentUser, IModeratorDirectory moderators)
    : AuthorizationHandler<ModeratorRequirement>
{
    protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, ModeratorRequirement requirement)
    {
        if (moderators.IsModerator(currentUser.FirebaseUid))
            context.Succeed(requirement);
        return Task.CompletedTask;
    }
}
