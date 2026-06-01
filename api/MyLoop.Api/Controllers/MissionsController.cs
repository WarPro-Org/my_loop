using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Data;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

[ApiController]
[Route("api/missions")]
public class MissionsController : ControllerBase
{
    private readonly IMissionService _missionService;
    private readonly AppDbContext _db;

    public MissionsController(IMissionService missionService, AppDbContext db)
    {
        _missionService = missionService;
        _db = db;
    }

    /// <summary>Get today's daily missions for a user (generates them if not yet created).</summary>
    [HttpGet("{userId:guid}")]
    public async Task<IActionResult> GetMissions([FromRoute] Guid userId)
    {
        var missions = await _missionService.GetTodaysMissions(userId);
        return Ok(missions.Select(m => new
        {
            m.Id,
            m.Type,
            m.Description,
            m.TargetValue,
            m.CurrentProgress,
            m.XpReward,
            m.IsCompleted,
            m.CompletedAt,
        }));
    }

    /// <summary>Get user's XP and level info.</summary>
    [HttpGet("xp/{userId:guid}")]
    public async Task<IActionResult> GetXpInfo([FromRoute] Guid userId)
    {
        var user = await _db.Users.FindAsync(userId);
        if (user == null) return NotFound();

        var currentLevelXp = MyLoop.Api.Constants.GameConstants.XpForLevel(user.Level);
        var nextLevelXp = MyLoop.Api.Constants.GameConstants.XpForLevel(user.Level + 1);
        var progressXp = user.TotalXp - currentLevelXp;
        var neededXp = nextLevelXp - currentLevelXp;

        return Ok(new
        {
            user.TotalXp,
            user.Level,
            ProgressXp = progressXp,
            NeededXp = neededXp,
            ProgressPercent = neededXp > 0 ? Math.Round(progressXp * 100.0 / neededXp, 1) : 100.0,
        });
    }


}
