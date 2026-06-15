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
    private readonly ILogger<AchievementsController> _logger;

    public AchievementsController(IAchievementService achievementService, ILogger<AchievementsController> logger)
    {
        _achievementService = achievementService;
        _logger = logger;
    }

    /// <summary>Get all achievements with user's progress and unlock status.</summary>
    [HttpGet("{userId:guid}")]
    public async Task<IActionResult> GetAchievements([FromRoute] Guid userId)
    {
        _logger.LogInformation("Fetching achievements for user {UserId}", userId);
        var achievements = await _achievementService.GetAllForUser(userId);
        return Ok(achievements);
    }
}
