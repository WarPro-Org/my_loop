using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/achievements")]
public class AchievementsController : ControllerBase
{
    private readonly IAchievementService _achievementService;

    public AchievementsController(IAchievementService achievementService)
    {
        _achievementService = achievementService;
    }

    /// <summary>Get all achievements with user's progress and unlock status.</summary>
    [HttpGet("{userId:guid}")]
    public async Task<IActionResult> GetAchievements([FromRoute] Guid userId)
    {
        var achievements = await _achievementService.GetAllForUser(userId);
        return Ok(achievements);
    }
}
