using System.Text;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;
using MyLoop.Api.Constants;
using MyLoop.Api.Options;

namespace MyLoop.Api.Services.Moderation.Alerts;

/// <summary>
/// Emails moderation alerts over SMTP (MailKit). Registered only when Moderation:Email:Host is
/// set. The body tells the moderator which endpoint to call; it never names the reporters.
/// </summary>
public sealed class SmtpModerationAlertChannel(IOptions<ModerationEmailOptions> options) : IModerationAlertChannel
{
    private const string SubjectPrefix = "[MyLoop moderation]";

    public string Name => "email";

    public async Task SendAsync(ModerationAlert alert, CancellationToken cancellationToken)
    {
        var settings = options.Value;
        // Only registered when Host is set (ModerationExtensions); guard anyway rather than assume.
        var host = settings.Host ?? throw new InvalidOperationException("Moderation email channel used without Moderation:Email:Host");
        var message = new MimeMessage();
        message.From.Add(MailboxAddress.Parse(settings.From));
        foreach (var recipient in settings.To)
            message.To.Add(MailboxAddress.Parse(recipient));
        message.Subject = BuildSubject(alert);
        message.Body = new TextPart("plain") { Text = BuildBody(alert) };

        using var client = new SmtpClient
        {
            Timeout = (int)TimeSpan.FromSeconds(InfrastructureDefaults.ModerationSmtpTimeoutSeconds).TotalMilliseconds,
        };
        var security = settings.UseStartTls ? SecureSocketOptions.StartTls : SecureSocketOptions.SslOnConnect;
        await client.ConnectAsync(host, settings.Port, security, cancellationToken);
        if (!string.IsNullOrEmpty(settings.Username))
            await client.AuthenticateAsync(settings.Username, settings.Password ?? "", cancellationToken);
        await client.SendAsync(message, cancellationToken);
        await client.DisconnectAsync(quit: true, cancellationToken);
    }

    internal static string BuildSubject(ModerationAlert alert) => alert.Kind switch
    {
        ModerationAlertKind.FirstReport => $"{SubjectPrefix} Name reported: {alert.NameSnapshot}",
        ModerationAlertKind.AutoHidden => $"{SubjectPrefix} Name auto-hidden: {alert.NameSnapshot}",
        ModerationAlertKind.RescanDigest => $"{SubjectPrefix} Rescan hid {alert.Details.Count} name(s)",
        _ => SubjectPrefix,
    };

    internal static string BuildBody(ModerationAlert alert)
    {
        var body = new StringBuilder();
        if (alert.Kind == ModerationAlertKind.RescanDigest)
        {
            body.AppendLine("A blocklist rescan hid these names. Review each case:");
            foreach (var line in alert.Details) body.AppendLine($"  {line}");
        }
        else
        {
            body.AppendLine($"Name:    {alert.NameSnapshot}");
            body.AppendLine($"User:    {alert.UserId}");
            body.AppendLine($"Case:    {alert.CaseId}");
            body.AppendLine($"Reports: {alert.ReportCount}");
        }
        body.AppendLine();
        body.AppendLine("Open cases:  GET  /api/moderation/cases?status=open (or autoHidden)");
        body.AppendLine("Confirm:     POST /api/moderation/cases/{caseId}/confirm");
        body.AppendLine("Restore:     POST /api/moderation/cases/{caseId}/restore");
        return body.ToString();
    }
}
