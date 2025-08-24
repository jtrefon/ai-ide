using System.Diagnostics;
using System.Text;

namespace Ide.Core.Utils;

public sealed class Runner : IRunner
{
    public async Task<RunResult> RunAsync(
        string fileName,
        IEnumerable<string>? args = null,
        string? workingDirectory = null,
        IDictionary<string, string?>? env = null,
        TimeSpan? timeout = null,
        int? outputMaxBytes = null,
        CancellationToken ct = default)
    {
        var sw = Stopwatch.StartNew();
        int cap = outputMaxBytes ?? (512 * 1024); // 512KB default per stream
        TimeSpan to = timeout ?? TimeSpan.FromSeconds(120);

        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        if (!string.IsNullOrWhiteSpace(workingDirectory))
        {
            psi.WorkingDirectory = workingDirectory!;
        }
        if (args != null)
        {
            foreach (var a in args)
            {
                psi.ArgumentList.Add(a);
            }
        }
        if (env != null)
        {
            foreach (var kv in env)
            {
                if (kv.Value is null)
                {
                    psi.Environment.Remove(kv.Key);
                }
                else
                {
                    psi.Environment[kv.Key] = kv.Value;
                }
            }
        }

        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };

        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        int outBytes = 0, errBytes = 0;
        var stdoutTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var stderrTcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        void OnOut(object? s, DataReceivedEventArgs e)
        {
            if (e.Data is null) return;
            var line = e.Data + "\n";
            var b = Encoding.UTF8.GetByteCount(line);
            if (outBytes + b <= cap)
            {
                stdout.Append(line);
                outBytes += b;
            }
            else if (outBytes < cap)
            {
                // append truncated tail to exactly reach cap
                int remaining = cap - outBytes;
                if (remaining > 0)
                {
                    var bytes = Encoding.UTF8.GetBytes(line);
                    var truncated = Encoding.UTF8.GetString(bytes, 0, remaining);
                    stdout.Append(truncated);
                    outBytes = cap;
                }
            }
        }
        void OnErr(object? s, DataReceivedEventArgs e)
        {
            if (e.Data is null) return;
            var line = e.Data + "\n";
            var b = Encoding.UTF8.GetByteCount(line);
            if (errBytes + b <= cap)
            {
                stderr.Append(line);
                errBytes += b;
            }
            else if (errBytes < cap)
            {
                int remaining = cap - errBytes;
                if (remaining > 0)
                {
                    var bytes = Encoding.UTF8.GetBytes(line);
                    var truncated = Encoding.UTF8.GetString(bytes, 0, remaining);
                    stderr.Append(truncated);
                    errBytes = cap;
                }
            }
        }

        try
        {
            try
            {
                if (!proc.Start())
                {
                    sw.Stop();
                    return new RunResult(ExitCode: -1, TimedOut: false, StartFailed: true,
                        Stdout: stdout.ToString(), Stderr: stderr.ToString(), Duration: sw.Elapsed);
                }
            }
            catch (Exception ex)
            {
                sw.Stop();
                stderr.AppendLine(ex.Message);
                return new RunResult(ExitCode: -1, TimedOut: false, StartFailed: true,
                    Stdout: stdout.ToString(), Stderr: stderr.ToString(), Duration: sw.Elapsed);
            }

            proc.OutputDataReceived += OnOut;
            proc.ErrorDataReceived += OnErr;
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(to);

            try
            {
                await proc.WaitForExitAsync(cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                try { proc.Kill(entireProcessTree: true); } catch { }
                await proc.WaitForExitAsync().ConfigureAwait(false);
                sw.Stop();
                return new RunResult(ExitCode: -1, TimedOut: true, StartFailed: false,
                    Stdout: stdout.ToString(), Stderr: stderr.ToString(), Duration: sw.Elapsed);
            }

            sw.Stop();
            return new RunResult(ExitCode: proc.ExitCode, TimedOut: false, StartFailed: false,
                Stdout: stdout.ToString(), Stderr: stderr.ToString(), Duration: sw.Elapsed);
        }
        finally
        {
            try
            {
                proc.OutputDataReceived -= OnOut;
                proc.ErrorDataReceived -= OnErr;
            }
            catch { }
        }
    }
}
