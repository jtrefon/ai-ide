using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Ide.Core.Utils;
using Xunit;

namespace Ide.Tests;

public class RunnerTests
{
    private static (string exe, string[] args) SleepCommand(int seconds)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return ("powershell", new[] { "-NoProfile", "-Command", $"Start-Sleep -Seconds {seconds}" });
        }
        else
        {
            return ("sh", new[] { "-c", $"sleep {seconds}" });
        }
    }

    private static (string exe, string[] args) BigOutputCommand()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            // Produce a lot of output via PowerShell
            // 10k lines of 200 chars ~ 2MB
            return ("powershell", new[] { "-NoProfile", "-Command",
                "$s='x'*200; for($i=0;$i -lt 10000; $i++){ Write-Output $s }" });
        }
        else
        {
            // yes generates endless 'y' with newlines; head caps total bytes
            return ("sh", new[] { "-c", "yes y | head -c 2097152" });
        }
    }

    [Fact]
    public async Task Run_Succeeds_DotnetVersion()
    {
        var runner = new Runner();
        var res = await runner.RunAsync("dotnet", new[] { "--version" }, timeout: TimeSpan.FromSeconds(20));
        Assert.False(res.StartFailed);
        Assert.False(res.TimedOut);
        Assert.Equal(0, res.ExitCode);
        Assert.False(string.IsNullOrWhiteSpace(res.Stdout));
    }

    [Fact]
    public async Task Run_TimesOut()
    {
        var runner = new Runner();
        var (exe, args) = SleepCommand(5);
        var res = await runner.RunAsync(exe, args, timeout: TimeSpan.FromMilliseconds(500));
        Assert.True(res.TimedOut);
        Assert.Equal(-1, res.ExitCode);
    }

    [Fact]
    public async Task Run_StartFailed_WhenExecutableMissing()
    {
        var runner = new Runner();
        var res = await runner.RunAsync("this_exe_does_not_exist_12345", new[] { "arg1" }, timeout: TimeSpan.FromSeconds(5));
        Assert.True(res.StartFailed);
        Assert.Equal(-1, res.ExitCode);
    }

    [Fact]
    public async Task Run_Respects_OutputCap()
    {
        var runner = new Runner();
        var (exe, args) = BigOutputCommand();
        int cap = 8192; // 8KB
        var res = await runner.RunAsync(exe, args, timeout: TimeSpan.FromSeconds(10), outputMaxBytes: cap);
        Assert.False(res.StartFailed);
        Assert.False(res.TimedOut);
        Assert.True(res.Stdout.Length <= cap, $"Stdout length {res.Stdout.Length} should be <= cap {cap}");
    }
}
