namespace MyLoop.Api.Options;

/// <summary>Name moderation settings (section <c>Moderation</c>, DR-002b).</summary>
public sealed class ModerationOptions
{
    public const string SectionName = "Moderation";

    /// <summary>
    /// Firebase UIDs allowed to call the moderator endpoints. Set per environment (env var
    /// <c>Moderation__ModeratorUids__0</c>, gitignored config); empty means nobody is a moderator.
    /// </summary>
    public string[] ModeratorUids { get; init; } = [];
}
