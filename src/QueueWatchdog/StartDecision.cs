namespace QueueWatchdog;

/// <summary>
/// How many runner executions to start for one repository, from its workflow jobs and its runner job's executions
/// (docs/DECISIONS.md D26). Only jobs queued for longer than the scaler normally takes count: the scaler starts the
/// others. Executions already running and not busy with a job will take queued jobs, so they are subtracted, and the
/// runner job's maximum is never exceeded.
/// </summary>
public static class StartDecision
{
    public static StartPlan Plan(
        IEnumerable<WorkflowJob> jobs,
        IReadOnlySet<string> runnerLabels,
        int runningExecutions,
        int maxExecutions,
        TimeSpan stuckAfter,
        DateTimeOffset now)
    {
        var ours = jobs.Where(job => CanRunOn(job, runnerLabels)).ToList();
        var stuck = ours.Count(job => job.Status == "queued" && now - job.CreatedAt >= stuckAfter);
        var busy = ours.Count(job => job.Status == "in_progress");

        var idle = Math.Max(0, runningExecutions - busy);
        var free = Math.Max(0, maxExecutions - runningExecutions);
        var toStart = Math.Min(Math.Max(0, stuck - idle), free);
        return new StartPlan(stuck, busy, idle, toStart);
    }

    // As the scaler with noDefaultLabels: a job runs here when every label it asks for is one of the runners' labels.
    private static bool CanRunOn(WorkflowJob job, IReadOnlySet<string> runnerLabels) =>
        job.Labels.Count > 0 && job.Labels.All(runnerLabels.Contains);
}

public sealed record WorkflowJob(string Status, IReadOnlyList<string> Labels, DateTimeOffset CreatedAt);

/// <param name="Stuck">Jobs for these runners queued for longer than the scaler normally takes.</param>
/// <param name="Busy">Jobs for these runners in progress, each on an execution.</param>
/// <param name="Idle">Running executions not busy with a job: they will take queued jobs.</param>
/// <param name="ToStart">Executions to start now.</param>
public sealed record StartPlan(int Stuck, int Busy, int Idle, int ToStart);
