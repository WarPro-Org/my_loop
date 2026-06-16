using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Controllers;

/// <summary>Liveness probe. Anonymous so load balancers and uptime checks need no token.</summary>
[ApiController]
public class HealthController : ControllerBase
{
    [AllowAnonymous]
    [HttpGet(ApiRoutes.Health)]
    public IActionResult Get() => Content("MyLoop API is running");
}
