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

    /// <summary>
    /// A blank entry (e.g. an env var set to "") would never match a real UID, so it silently
    /// leaves the intended moderator without access; refuse it at startup instead.
    /// </summary>
    public bool IsValid() => ModeratorUids.All(uid => !string.IsNullOrWhiteSpace(uid));
}
