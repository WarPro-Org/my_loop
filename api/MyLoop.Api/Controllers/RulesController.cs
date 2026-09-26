using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using MyLoop.Api.Constants;
using MyLoop.Modules.Rules;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Hands the app the rules it needs (FR1). The ETag is a fingerprint of those rules, so an app
/// that already has them gets 304 Not Modified and keeps its saved copy.
/// </summary>
[ApiController]
[Route(ApiRoutes.Rules)]
[Authorize]
public class RulesController : ControllerBase
{
    private readonly IRuleSettings _rules;

    public RulesController(IRuleSettings rules)
    {
        _rules = rules;
    }

    [HttpGet]
    public IActionResult Get()
    {
        var etag = new EntityTagHeaderValue($"\"{_rules.ClientRulesTag}\"");

        Response.GetTypedHeaders().ETag = etag;
        var ifNoneMatch = Request.GetTypedHeaders().IfNoneMatch;
        if (ifNoneMatch.Any(tag => tag.Compare(etag, useStrongComparison: false)))
            return StatusCode(StatusCodes.Status304NotModified);

        return Ok(_rules.GetClientRules());
    }
}
