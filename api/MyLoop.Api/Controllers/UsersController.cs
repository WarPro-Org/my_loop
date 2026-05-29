using Microsoft.AspNetCore.Mvc;
using MyLoop.Api.Models;
using MyLoop.Api.Services;

namespace MyLoop.Api.Controllers;

/// <summary>
/// Handles user registration, profile lookup, and profile updates.
/// </summary>
[ApiController]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly IUserService _userService;
    private readonly IValidationService _validation;

    public UsersController(IUserService userService, IValidationService validation)
    {
        _userService = userService;
        _validation = validation;
    }

    /// <summary>
    /// Register a new user. Called once after sign-in.
    /// </summary>
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        // Validate inputs
        var nameError = _validation.ValidateDisplayName(request.DisplayName);
        if (nameError != null) return BadRequest(nameError);

        var colorError = _validation.ValidateColor(request.Color);
        if (colorError != null) return BadRequest(colorError);

        var avatarError = _validation.ValidateAvatarId(request.AvatarId);
        if (avatarError != null) return BadRequest(avatarError);

        var user = await _userService.Register(request);
        return Created($"/api/users/{user.Id}", user);
    }

    /// <summary>
    /// Get a user by their internal ID.
    /// </summary>
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById([FromRoute] Guid id)
    {
        var user = await _userService.GetById(id);
        if (user == null) return NotFound();
        return Ok(user);
    }

    /// <summary>
    /// Look up a user by Firebase UID — used for login.
    /// </summary>
    [HttpGet("by-uid/{firebaseUid}")]
    public async Task<IActionResult> GetByFirebaseUid([FromRoute] string firebaseUid)
    {
        var user = await _userService.GetByFirebaseUid(firebaseUid);
        if (user == null) return NotFound();
        return Ok(user);
    }

    /// <summary>
    /// Update a user's avatar, color, or display name.
    /// </summary>
    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update([FromRoute] Guid id, [FromBody] UpdateUserRequest request)
    {
        // Validate any provided fields
        if (request.DisplayName != null)
        {
            var nameError = _validation.ValidateDisplayName(request.DisplayName);
            if (nameError != null) return BadRequest(nameError);
        }
        if (request.Color != null)
        {
            var colorError = _validation.ValidateColor(request.Color);
            if (colorError != null) return BadRequest(colorError);
        }
        if (request.AvatarId != null)
        {
            var avatarError = _validation.ValidateAvatarId(request.AvatarId.Value);
            if (avatarError != null) return BadRequest(avatarError);
        }

        var user = await _userService.UpdateProfile(id, request);
        if (user == null) return NotFound();
        return Ok(user);
    }

    /// <summary>
    /// Get a user's rich public profile (includes rank, stats, etc.)
    /// </summary>
    [HttpGet("{id:guid}/profile")]
    public async Task<IActionResult> GetProfile([FromRoute] Guid id)
    {
        var profile = await _userService.GetRichProfile(id);
        if (profile == null) return NotFound();
        return Ok(profile);
    }
}
