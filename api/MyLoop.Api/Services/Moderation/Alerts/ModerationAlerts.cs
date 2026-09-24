using System.Threading.Channels;
using MyLoop.Api.Constants;

namespace MyLoop.Api.Services.Moderation.Alerts;

/// <summary>Raises moderation alerts without blocking the request that caused them.</summary>
public interface IModerationAlerts
{
    /// <summary>Queues the alert for background delivery. Never throws and never waits on I/O.</summary>
    void Raise(ModerationAlert alert);
}

/// <summary>
/// Bounded in-memory queue between request handlers and <see cref="ModerationAlertDispatcher"/>.
/// Alerts are best-effort: the NameModerationCases table is the source of truth, and every alert
/// is logged when raised, so one that is dropped (queue full, process restart) is still
/// recoverable from the moderator queue and the logs.
/// </summary>
public sealed class ModerationAlertQueue(ILogger<ModerationAlertQueue> logger) : IModerationAlerts
{
    private readonly Channel<ModerationAlert> _channel = Channel.CreateBounded<ModerationAlert>(
        new BoundedChannelOptions(InfrastructureDefaults.ModerationAlertQueueCapacity)
        {
            FullMode = BoundedChannelFullMode.DropWrite,
            SingleReader = true,
        });

    public ChannelReader<ModerationAlert> Reader => _channel.Reader;

    public void Raise(ModerationAlert alert)
    {
        logger.LogInformation(
            "ModerationAlertRaised {Kind} case {CaseId} user {UserId} name {NameSnapshot} reports {ReportCount}",
            alert.Kind, alert.CaseId, alert.UserId, alert.NameSnapshot, alert.ReportCount);

        if (!_channel.Writer.TryWrite(alert))
            logger.LogWarning("Moderation alert queue full; {Kind} for case {CaseId} not delivered", alert.Kind, alert.CaseId);
    }
}

/// <summary>Delivers queued alerts to every registered <see cref="IModerationAlertChannel"/>.</summary>
public sealed class ModerationAlertDispatcher(
    ModerationAlertQueue queue,
    IEnumerable<IModerationAlertChannel> channels,
    ILogger<ModerationAlertDispatcher> logger) : BackgroundService
{
    private readonly IReadOnlyList<IModerationAlertChannel> _channels = channels.ToList();

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (_channels.Count == 0)
            logger.LogInformation("No moderation alert channels configured; alerts are logged only");

        await foreach (var alert in queue.Reader.ReadAllAsync(stoppingToken))
            await DeliverAsync(alert, stoppingToken);
    }

    /// <summary>Sends one alert to all channels; a failing channel never blocks the others.</summary>
    internal async Task DeliverAsync(ModerationAlert alert, CancellationToken cancellationToken)
    {
        foreach (var channel in _channels)
        {
            try
            {
                await channel.SendAsync(alert, cancellationToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Moderation alert channel {Channel} failed for {Kind} case {CaseId}",
                    channel.Name, alert.Kind, alert.CaseId);
            }
        }
    }
}
