using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Models;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Handles territory claim submission.
/// </summary>
[ApiController]
[Route("api/claims")]
[Authorize]
public class ClaimsController : ControllerBase
{
    private readonly ITerritoryService _territoryService;

    public ClaimsController(ITerritoryService territoryService)
    {
        _territoryService = territoryService;
    }

    /// <summary>
    /// Submit a territory claim. The user walked a path — we compute
    /// which hexes they captured and assign ownership.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> SubmitClaim([FromBody] ClaimRequest request)
    {
        var result = await _territoryService.ProcessClaim(request.UserId, request.Path);

        if (!result.Success)
        {
            return BadRequest(result.Error);
        }

        return Created($"/api/claims/{result.Data!.Id}", result.Data);
    }
}
