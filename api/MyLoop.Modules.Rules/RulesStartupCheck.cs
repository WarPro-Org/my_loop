using Microsoft.Extensions.Hosting;

namespace MyLoop.Modules.Rules;

/// <summary>
/// Builds <see cref="IRuleSettings"/> while the server starts: the host creates its hosted services on start,
/// and taking the rules here builds them. Anything that fails while building them stops startup instead of
/// turning the first rules request into a 500.
/// </summary>
internal sealed class RulesStartupCheck(IRuleSettings rules) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        _ = rules.ClientRulesTag;
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
