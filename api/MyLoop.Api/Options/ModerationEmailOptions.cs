using System.Net;
using MimeKit;

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
    private const int MinPort = 1; // port 0 means "any free port", never a server to connect to

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

    /// <summary>
    /// An enabled channel needs a usable port and addresses that parse. Checked at startup: a bad
    /// address would otherwise fail every send at runtime, each failure only a logged warning.
    /// </summary>
    public bool IsValid() =>
        !IsEnabled
        || (Port is >= MinPort and <= IPEndPoint.MaxPort
            && IsMailbox(From)
            && To.Length > 0
            && To.All(IsMailbox));

    /// <summary>What <see cref="MailboxAddress.Parse(string)"/> will accept at send time, with a domain.</summary>
    private static bool IsMailbox(string? text) =>
        !string.IsNullOrWhiteSpace(text)
        && MailboxAddress.TryParse(text, out var mailbox)
        && mailbox.Address.Contains('@');
}
