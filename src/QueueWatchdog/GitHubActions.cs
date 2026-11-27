using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace QueueWatchdog;

/// <summary>
/// The GitHub REST calls of the watchdog, as the Scaler App (Actions: read). Runs are listed without a status filter:
/// a run missing from the status-filtered list is what the watchdog is for (docs/experiments/09-queue-watchdog.md).
/// </summary>
public sealed class GitHubActions(HttpClient http)
{
    public const string ApiVersion = "2026-03-10";
    // The most recent runs: an unfinished run older than the last 50 would need 50 newer runs within its wait.
    private const int RecentRuns = 50;

    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };

    public static void Configure(HttpClient http)
    {
        http.BaseAddress = new Uri("https://api.github.com/");
        http.Timeout = TimeSpan.FromSeconds(30);
        http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        http.DefaultRequestHeaders.Add("X-GitHub-Api-Version", ApiVersion);
        http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("runner-queue-watchdog", "1.0"));
    }

    /// <summary>An installation token for these repositories only, with Actions: read only.</summary>
    public async Task<string> InstallationToken(string appJwt, string installationId, IEnumerable<string> repositories, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"app/installations/{installationId}/access_tokens")
        {
            Content = JsonContent.Create(new { repositories, permissions = new { actions = "read" } }),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", appJwt);
        var token = await Send<InstallationTokenResponse>(request, cancellationToken);
        return token.Token;
    }

    /// <summary>The jobs of the repository's unfinished runs, among its most recent runs.</summary>
    public async Task<IReadOnlyList<WorkflowJob>> JobsOfUnfinishedRuns(string token, string owner, string repository, CancellationToken cancellationToken)
    {
        var runs = await Get<WorkflowRunsResponse>(token, $"repos/{owner}/{repository}/actions/runs?per_page={RecentRuns}", cancellationToken);
        var jobs = new List<WorkflowJob>();
        foreach (var run in runs.WorkflowRuns.Where(run => run.Status != "completed"))
        {
            var runJobs = await Get<WorkflowJobsResponse>(token, $"repos/{owner}/{repository}/actions/runs/{run.Id}/jobs?per_page=100", cancellationToken);
            jobs.AddRange(runJobs.Jobs.Select(job => new WorkflowJob(job.Status, job.Labels, job.CreatedAt)));
        }
        return jobs;
    }

    private async Task<T> Get<T>(string token, string path, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await Send<T>(request, cancellationToken);
    }

    private async Task<T> Send<T>(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            // The path only: the query and the headers are left out of the message.
            throw new HttpRequestException($"GitHub answered {(int)response.StatusCode} to {request.Method} {request.RequestUri?.AbsolutePath}", null, response.StatusCode);
        }
        return await response.Content.ReadFromJsonAsync<T>(Json, cancellationToken)
            ?? throw new HttpRequestException($"GitHub sent an empty answer to {request.Method} {request.RequestUri?.AbsolutePath}");
    }

    private sealed record InstallationTokenResponse(string Token);

    private sealed record WorkflowRunsResponse(List<WorkflowRunItem> WorkflowRuns);

    private sealed record WorkflowRunItem(long Id, string Status);

    private sealed record WorkflowJobsResponse(List<WorkflowJobItem> Jobs);

    private sealed record WorkflowJobItem(string Status, List<string> Labels, DateTimeOffset CreatedAt);
}
