namespace QueueWatchdog.Tests;

public class StartDecisionTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 27, 18, 0, 0, TimeSpan.Zero);
    private static readonly IReadOnlySet<string> RunnerLabels = new HashSet<string>(["aca-agent"], StringComparer.OrdinalIgnoreCase);
    private static readonly TimeSpan StuckAfter = TimeSpan.FromMinutes(5);

    private static WorkflowJob Queued(int minutesAgo, params string[] labels) =>
        new("queued", labels.Length > 0 ? labels : ["aca-agent"], Now.AddMinutes(-minutesAgo));

    private static WorkflowJob InProgress() => new("in_progress", ["aca-agent"], Now.AddMinutes(-10));

    private static StartPlan Plan(int running, params WorkflowJob[] jobs) =>
        StartDecision.Plan(jobs, RunnerLabels, running, maxExecutions: 3, StuckAfter, Now);

    [Fact]
    public void Jobs_the_scaler_missed_get_one_execution_each()
    {
        // The 2026-11-27 incident: three jobs queued for 80 minutes, nothing running.
        var plan = Plan(0, Queued(80), Queued(80), Queued(80));
        Assert.Equal(new StartPlan(Stuck: 3, Busy: 0, Idle: 0, ToStart: 3), plan);
    }

    [Fact]
    public void A_job_queued_for_less_than_the_wait_is_left_to_the_scaler() =>
        Assert.Equal(0, Plan(0, Queued(4)).ToStart);

    [Fact]
    public void A_job_queued_for_exactly_the_wait_counts_as_stuck() =>
        Assert.Equal(1, Plan(0, Queued(5)).ToStart);

    [Fact]
    public void Idle_executions_take_queued_jobs_before_new_ones_start()
    {
        // Two executions running, one busy: one idle execution will take one of the two queued jobs.
        var plan = Plan(2, InProgress(), Queued(10), Queued(10));
        Assert.Equal(new StartPlan(Stuck: 2, Busy: 1, Idle: 1, ToStart: 1), plan);
    }

    [Fact]
    public void Busy_executions_do_not_count_as_idle() =>
        Assert.Equal(1, Plan(1, InProgress(), Queued(10)).ToStart);

    [Fact]
    public void The_runner_jobs_maximum_is_never_exceeded()
    {
        // Three busy executions at the maximum: the fourth job waits for one to end, as with the scaler.
        var plan = Plan(3, InProgress(), InProgress(), InProgress(), Queued(10));
        Assert.Equal(0, plan.ToStart);
    }

    [Fact]
    public void Jobs_for_other_runners_are_ignored()
    {
        var plan = Plan(0, Queued(10, "ubuntu-latest"), Queued(10, "aca-agent", "gpu"));
        Assert.Equal(new StartPlan(Stuck: 0, Busy: 0, Idle: 0, ToStart: 0), plan);
    }

    [Fact]
    public void Labels_match_whatever_their_case() =>
        Assert.Equal(1, Plan(0, Queued(10, "ACA-Agent")).ToStart);

    [Fact]
    public void Nothing_starts_while_nothing_waits() =>
        Assert.Equal(0, Plan(1).ToStart);
}
