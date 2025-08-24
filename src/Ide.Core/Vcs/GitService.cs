using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Ide.Core.Utils;

namespace Ide.Core.Vcs;

public sealed class GitService : IGitService
{
    private readonly IRunner _runner;

    public GitService(IRunner? runner = null)
    {
        _runner = runner ?? new Runner();
    }

    private Task<RunResult> RunGitAsync(string repoRoot, IEnumerable<string> args, CancellationToken ct)
        => _runner.RunAsync("git", args, workingDirectory: repoRoot, ct: ct, timeout: TimeSpan.FromSeconds(30));

    public async Task<bool> IsRepoAsync(string repoRoot, CancellationToken ct = default)
    {
        var r = await RunGitAsync(repoRoot, new[] { "rev-parse", "--is-inside-work-tree" }, ct);
        return !r.StartFailed && !r.TimedOut && r.ExitCode == 0 && r.Stdout.Trim().Equals("true", StringComparison.OrdinalIgnoreCase);
    }

    public async Task<string> StatusAsync(string repoRoot, bool porcelain = true, CancellationToken ct = default)
    {
        var args = porcelain ? new[] { "status", "--porcelain" } : new[] { "status" };
        var r = await RunGitAsync(repoRoot, args, ct);
        return r.Stdout;
    }

    public async Task<string> CurrentBranchAsync(string repoRoot, CancellationToken ct = default)
    {
        var r = await RunGitAsync(repoRoot, new[] { "rev-parse", "--abbrev-ref", "HEAD" }, ct);
        return r.Stdout.Trim();
    }

    public async Task<IReadOnlyList<string>> BranchListAsync(string repoRoot, CancellationToken ct = default)
    {
        var r = await RunGitAsync(repoRoot, new[] { "branch", "--list" }, ct);
        var lines = r.Stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(s => s.TrimStart('*', ' ', '\t').Trim()).ToArray();
        return lines;
    }

    public async Task<bool> CheckoutAsync(string repoRoot, string branch, bool create = false, CancellationToken ct = default)
    {
        var args = create ? new[] { "checkout", "-b", branch } : new[] { "checkout", branch };
        var r = await RunGitAsync(repoRoot, args, ct);
        return r.ExitCode == 0 && !r.TimedOut && !r.StartFailed;
    }

    public async Task<bool> CommitAllAsync(string repoRoot, string message, CancellationToken ct = default)
    {
        // Stage everything
        var add = await RunGitAsync(repoRoot, new[] { "add", "." }, ct);
        if (add.ExitCode != 0) return false;

        // Commit (allow empty message properly)
        var commit = await RunGitAsync(repoRoot, new[] { "commit", "-m", message }, ct);
        return commit.ExitCode == 0;
    }
}
