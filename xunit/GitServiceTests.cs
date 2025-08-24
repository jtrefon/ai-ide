using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using Ide.Core.Utils;
using Ide.Core.Vcs;
using Xunit;

namespace Ide.Tests;

public class GitServiceTests
{
    private static string CreateTempDir()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ide-git-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static async Task InitRepoAsync(string root)
    {
        var runner = new Runner();
        var r1 = await runner.RunAsync("git", new[] { "init" }, workingDirectory: root, timeout: TimeSpan.FromSeconds(15));
        Assert.Equal(0, r1.ExitCode);
        // Ensure identity for commits
        var r2 = await runner.RunAsync("git", new[] { "config", "user.email", "tester@example.com" }, workingDirectory: root);
        Assert.Equal(0, r2.ExitCode);
        var r3 = await runner.RunAsync("git", new[] { "config", "user.name", "Test User" }, workingDirectory: root);
        Assert.Equal(0, r3.ExitCode);
    }

    [Fact]
    public async Task GitService_Flow_Works()
    {
        var root = CreateTempDir();
        await InitRepoAsync(root);

        var git = new GitService();
        Assert.True(await git.IsRepoAsync(root));

        // Create a file, verify status shows untracked
        var file = Path.Combine(root, "a.txt");
        await File.WriteAllTextAsync(file, "hello", new UTF8Encoding(false));
        var status1 = await git.StatusAsync(root);
        Assert.Contains("?? a.txt", status1);

        // Commit all
        Assert.True(await git.CommitAllAsync(root, "chore: add a.txt"));
        var status2 = await git.StatusAsync(root);
        Assert.True(string.IsNullOrWhiteSpace(status2));

        // Create and checkout new branch
        Assert.True(await git.CheckoutAsync(root, "feature/test", create: true));
        var branch = await git.CurrentBranchAsync(root);
        Assert.Equal("feature/test", branch);

        // Modify file, expect modified status
        await File.WriteAllTextAsync(file, "world", new UTF8Encoding(false));
        var status3 = await git.StatusAsync(root);
        Assert.Contains(" M a.txt", status3);
    }
}
