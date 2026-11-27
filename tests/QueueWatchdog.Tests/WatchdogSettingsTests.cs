namespace QueueWatchdog.Tests;

public class WatchdogSettingsTests
{
    [Fact]
    public void Runner_jobs_are_read_as_repository_and_job_pairs()
    {
        var jobs = WatchdogSettings.ParseRunnerJobs(" my-app=job-runner-dev , my-mods=job-runner-dev-mods ,");

        Assert.Equal([new WatchedRunnerJob("my-app", "job-runner-dev"), new WatchedRunnerJob("my-mods", "job-runner-dev-mods")], jobs);
    }

    [Theory]
    [InlineData("my-app")]
    [InlineData("=job-runner-dev")]
    [InlineData("my-app=")]
    public void An_entry_that_is_not_a_pair_is_refused(string pairs) =>
        Assert.Throws<InvalidOperationException>(() => WatchdogSettings.ParseRunnerJobs(pairs));
}
