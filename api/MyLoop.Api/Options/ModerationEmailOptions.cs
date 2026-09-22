namespace MyLoop.Api.Options;

/// <summary>
/// SMTP delivery for moderation alerts (section <c>Moderation:Email</c>). Any SMTP provider works
/// (Workspace, SES, Postmark…). An empty <see cref="Host"/> disables the email channel and alerts
/// are only logged — so local dev and CI run without credentials.
/// </summary>
public sealed class ModerationEmailOptions
{
    public const string SectionName = "Moderation:Email";
    public const int DefaultSubmissionPort = 587;

    public string? Host { get; init; }
    public int Port { get; init; } = DefaultSubmissionPort;
    /// <summary>STARTTLS on the submission port; set false only for an implicit-TLS port (465).</summary>
    public bool UseStartTls { get; init; } = true;
    public string? Username { get; init; }
    /// <summary>Environment variable or gitignored config only — never committed, never logged.</summary>
    public string? Password { get; init; }
    public string From { get; init; } = "";
    public string[] To { get; init; } = [];

    public bool IsEnabled => !string.IsNullOrWhiteSpace(Host);

    /// <summary>An enabled channel with nowhere to send from or to is a misconfiguration.</summary>
    public bool IsValid() => !IsEnabled || (!string.IsNullOrWhiteSpace(From) && To.Length > 0);
}
