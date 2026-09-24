namespace MyLoop.Api.Services.Moderation.Alerts;

/// <summary>
/// One delivery channel for moderation alerts (email today; Slack later). Register any number;
/// <see cref="ModerationAlertDispatcher"/> delivers each alert to all of them, isolated from each other.
/// </summary>
public interface IModerationAlertChannel
{
    string Name { get; }
    Task SendAsync(ModerationAlert alert, CancellationToken cancellationToken);
}
