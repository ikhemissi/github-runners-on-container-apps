using Azure;
using Azure.ResourceManager;
using Azure.ResourceManager.AppContainers;
using Azure.ResourceManager.AppContainers.Models;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace QueueWatchdog;

/// <summary>
/// Every 5 minutes, starts runner executions for jobs that have waited too long for one (docs/DECISIONS.md D26): the
/// scale rule's scaler counts queued jobs from GitHub's status-filtered run list, which once left a queued run out
/// for 80 minutes (docs/experiments/09-queue-watchdog.md). For each watched repository: the jobs of its unfinished
/// runs, from the unfiltered list; its runner job's running executions; then StartDecision says how many to start.
/// A started execution registers a just-in-time runner like any other, and the runner's idle watchdog removes it if
/// the scaler has meanwhile started one for the same job.
/// </summary>
public class StartQueuedRunners(ArmClient arm, SecretClient scalerKeyVault, GitHubActions github, IConfiguration configuration, ILogger<StartQueuedRunners> logger)
{
    [Function(nameof(StartQueuedRunners))]
    public async Task Run([TimerTrigger("0 */5 * * * *")] TimerInfo timer, CancellationToken cancellationToken)
    {
        var settings = WatchdogSettings.From(configuration);
        var token = await ScalerToken(settings, cancellationToken);

        var failedRepositories = new List<string>();
        foreach (var watched in settings.RunnerJobs)
        {
            try
            {
                await Check(watched, settings, token, cancellationToken);
            }
            catch (Exception error) when (error is RequestFailedException or HttpRequestException)
            {
                // One repository's failure doesn't keep the others from being checked.
                logger.LogError(error, "{Repository}: check failed", watched.Repository);
                failedRepositories.Add(watched.Repository);
            }
        }

        if (failedRepositories.Count > 0)
        {
            throw new InvalidOperationException($"The check failed for {string.Join(", ", failedRepositories)}.");
        }
    }

    private async Task<string> ScalerToken(WatchdogSettings settings, CancellationToken cancellationToken)
    {
        var secretName = new KeyVaultSecretIdentifier(settings.ScalerKeySecretUri).Name;
        KeyVaultSecret key = await scalerKeyVault.GetSecretAsync(secretName, cancellationToken: cancellationToken);
        var appJwt = GitHubAppJwt.Create(settings.ScalerAppId, key.Value, DateTimeOffset.UtcNow);
        var repositories = settings.RunnerJobs.Select(watched => watched.Repository);
        return await github.InstallationToken(appJwt, settings.ScalerInstallationId, repositories, cancellationToken);
    }

    private async Task Check(WatchedRunnerJob watched, WatchdogSettings settings, string token, CancellationToken cancellationToken)
    {
        var jobs = await github.JobsOfUnfinishedRuns(token, settings.GitHubOwner, watched.Repository, cancellationToken);
        var runnerJob = arm.GetContainerAppJobResource(ContainerAppJobResource.CreateResourceIdentifier(
            settings.SubscriptionId, settings.ResourceGroupName, watched.JobName));
        var running = await RunningExecutions(runnerJob, cancellationToken);

        var plan = StartDecision.Plan(jobs, settings.RunnerLabels, running, settings.MaxExecutions, settings.StuckAfter, DateTimeOffset.UtcNow);
        logger.LogInformation(
            "{Repository}: {Stuck} job(s) queued for {StuckAfter} or more, {Busy} in progress, {Running} execution(s) running ({Idle} idle): starting {ToStart}",
            watched.Repository, plan.Stuck, settings.StuckAfter, plan.Busy, running, plan.Idle, plan.ToStart);

        if (plan.ToStart == 0)
        {
            return;
        }

        // The signal to look for (docs/OPERATIONS.md): the scaler missed queued jobs.
        logger.LogWarning("{Repository}: the scaler left {Stuck} job(s) without a runner; starting {ToStart} execution(s) of {Job}",
            watched.Repository, plan.Stuck, plan.ToStart, watched.JobName);
        for (var started = 0; started < plan.ToStart; started++)
        {
            await runnerJob.StartAsync(WaitUntil.Started, template: null, cancellationToken);
        }
    }

    private static async Task<int> RunningExecutions(ContainerAppJobResource runnerJob, CancellationToken cancellationToken)
    {
        var running = 0;
        await foreach (var execution in runnerJob.GetContainerAppJobExecutions().GetAllAsync(cancellationToken: cancellationToken))
        {
            var status = execution.Data.Status;
            if (status == JobExecutionRunningState.Running || status == JobExecutionRunningState.Processing)
            {
                running++;
            }
        }
        return running;
    }
}
