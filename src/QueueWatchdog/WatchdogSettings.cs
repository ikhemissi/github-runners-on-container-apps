using Microsoft.Extensions.Configuration;

namespace QueueWatchdog;

/// <summary>
/// The watchdog's app settings (infra/queue-watchdog.tf), read and checked once per run. RUNNER_JOBS lists the
/// runner jobs to watch as comma-separated repository=job pairs, e.g. "my-app=job-runner-dev,my-mods=job-runner-dev-mods".
/// </summary>
public sealed record WatchdogSettings(
    string SubscriptionId,
    string ResourceGroupName,
    string GitHubOwner,
    IReadOnlyList<WatchedRunnerJob> RunnerJobs,
    IReadOnlySet<string> RunnerLabels,
    int MaxExecutions,
    TimeSpan StuckAfter,
    string ScalerAppId,
    string ScalerInstallationId,
    Uri ScalerKeySecretUri)
{
    public static WatchdogSettings From(IConfiguration settings)
    {
        string Required(string name) =>
            settings[name] is { Length: > 0 } value ? value : throw new InvalidOperationException($"The app setting {name} is missing.");

        return new WatchdogSettings(
            SubscriptionId: Required("SUBSCRIPTION_ID"),
            ResourceGroupName: Required("RESOURCE_GROUP_NAME"),
            GitHubOwner: Required("GITHUB_OWNER"),
            RunnerJobs: ParseRunnerJobs(Required("RUNNER_JOBS")),
            RunnerLabels: SplitList(Required("RUNNER_LABELS")).ToHashSet(StringComparer.OrdinalIgnoreCase),
            MaxExecutions: int.Parse(Required("RUNNER_MAX_EXECUTIONS")),
            StuckAfter: TimeSpan.FromSeconds(int.Parse(Required("STUCK_AFTER_SECONDS"))),
            ScalerAppId: Required("SCALER_APP_ID"),
            ScalerInstallationId: Required("SCALER_INSTALLATION_ID"),
            ScalerKeySecretUri: new Uri(Required("SCALER_KEY_SECRET_URI")));
    }

    public static IReadOnlyList<WatchedRunnerJob> ParseRunnerJobs(string pairs) =>
        SplitList(pairs)
            .Select(pair => pair.Split('=', 2, StringSplitOptions.TrimEntries))
            .Select(parts => parts.Length == 2 && parts[0].Length > 0 && parts[1].Length > 0
                ? new WatchedRunnerJob(Repository: parts[0], JobName: parts[1])
                : throw new InvalidOperationException($"RUNNER_JOBS has an entry that is not repository=job: '{string.Join('=', parts)}'."))
            .ToList();

    private static IEnumerable<string> SplitList(string list) =>
        list.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
}

public sealed record WatchedRunnerJob(string Repository, string JobName);
