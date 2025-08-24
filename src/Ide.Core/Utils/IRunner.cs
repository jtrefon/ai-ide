using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Ide.Core.Utils;

public sealed record RunResult(
    int ExitCode,
    bool TimedOut,
    bool StartFailed,
    string Stdout,
    string Stderr,
    TimeSpan Duration
);

public interface IRunner
{
    /// <summary>
    /// Run a process with args, optional cwd and env, with timeout and output caps.
    /// </summary>
    /// <param name="fileName">Executable to run (on PATH or absolute).</param>
    /// <param name="args">Arguments (each as a separate item).</param>
    /// <param name="workingDirectory">Working directory.</param>
    /// <param name="env">Additional environment variables (null value removes var).</param>
    /// <param name="timeout">Timeout; defaults to 120 seconds.</param>
    /// <param name="outputMaxBytes">Cap for stdout/stderr each; defaults to 512 KB.</param>
    /// <param name="ct">Cancellation token.</param>
    Task<RunResult> RunAsync(
        string fileName,
        IEnumerable<string>? args = null,
        string? workingDirectory = null,
        IDictionary<string, string?>? env = null,
        TimeSpan? timeout = null,
        int? outputMaxBytes = null,
        CancellationToken ct = default);
}
