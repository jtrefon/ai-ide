using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Text.RegularExpressions;

namespace ide;

public sealed class ScriptTerminalBackend : ITerminalBackend
{
    public event Action<string>? Output;
    public event Action<string>? Error;

    private Process? _proc;
    private StreamWriter? _stdin;
    private CancellationTokenSource? _cts;

    public bool IsRunning => _proc is { HasExited: false };

    public void Start()
    {
        if (IsRunning) return;

        string shell = File.Exists("/bin/zsh") ? "/bin/zsh" : (File.Exists("/bin/bash") ? "/bin/bash" : "/bin/sh");
        bool isZsh = shell.EndsWith("/zsh", StringComparison.Ordinal);
        bool isBash = shell.EndsWith("/bash", StringComparison.Ordinal);

        bool useScript = File.Exists("/usr/bin/script");
        var psi = new ProcessStartInfo
        {
            FileName = useScript ? "/usr/bin/script" : shell,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Environment.CurrentDirectory,
        };
        // Keep colors disabled and simplify prompt; allow shell to behave interactively via script(1)
        psi.Environment["TERM"] = "xterm-256color";
        psi.Environment["CLICOLOR"] = "0";
        psi.Environment["NO_COLOR"] = "1";
        psi.Environment["PS1"] = "$ ";
        psi.Environment["PROMPT"] = "$ ";
        psi.Environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

        if (useScript)
        {
            // script -q avoids header; run the target shell interactively with minimal rc
            psi.ArgumentList.Add("-q");
            psi.ArgumentList.Add("/dev/null");
            psi.ArgumentList.Add(shell);
            if (isZsh)
            {
                psi.ArgumentList.Add("-f"); // no user rc files
                psi.ArgumentList.Add("-i"); // interactive
            }
            else if (isBash)
            {
                psi.ArgumentList.Add("--noprofile");
                psi.ArgumentList.Add("--norc");
                psi.ArgumentList.Add("-i");
            }
            else
            {
                psi.ArgumentList.Add("-i");
            }
        }
        else
        {
            if (isZsh)
            {
                psi.ArgumentList.Add("-f");
                psi.ArgumentList.Add("-i");
            }
            else if (isBash)
            {
                psi.ArgumentList.Add("--noprofile");
                psi.ArgumentList.Add("--norc");
                psi.ArgumentList.Add("-i");
            }
            else
            {
                psi.ArgumentList.Add("-i");
            }
        }

        _proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        _proc.Exited += (_, __) => Output?.Invoke("[terminal exited]\n");

        if (!_proc.Start())
        {
            Error?.Invoke("[terminal error] failed to start\n");
            return;
        }

        _stdin = _proc.StandardInput;
        _cts = new CancellationTokenSource();
        _ = StartReadLoop(_proc.StandardOutput.BaseStream, chunk => Output?.Invoke(Sanitize(chunk)), _cts.Token);
        _ = StartReadLoop(_proc.StandardError.BaseStream, chunk => Output?.Invoke(Sanitize(chunk)), _cts.Token);
        Output?.Invoke("[terminal started]\n");
    }

    public void Stop()
    {
        try
        {
            if (_proc is null) return;
            try { _stdin?.WriteLine("exit"); _stdin?.Flush(); } catch { }
            try { _cts?.Cancel(); } catch { }
            try { if (!_proc.HasExited) _proc.Kill(entireProcessTree: true); } catch { }
            try { _proc.WaitForExit(1000); } catch { }
        }
        finally
        {
            _proc = null;
            _stdin = null;
            _cts?.Dispose();
            _cts = null;
            Output?.Invoke("[terminal stopped]\n");
        }
    }

    private static readonly Regex AnsiCsi = new Regex("\u001B\\[[0-9;?]*[ -/]*[@-~]", RegexOptions.Compiled);
    private static readonly Regex AnsiOsc = new Regex("\u001B\u005D[^\u0007]*\u0007", RegexOptions.Compiled);
    private static string Sanitize(string chunk)
    {
        if (string.IsNullOrEmpty(chunk)) return chunk;
        var s = chunk.Replace("\r\n", "\n").Replace('\r', '\n');
        s = AnsiCsi.Replace(s, string.Empty);
        s = AnsiOsc.Replace(s, string.Empty);
        return s;
    }

    public void WriteLine(string text)
    {
        try
        {
            if (_stdin is null)
            {
                Error?.Invoke("[terminal] not started\n");
                return;
            }
            _stdin.WriteLine(text);
            _stdin.Flush();
        }
        catch (Exception ex)
        {
            Error?.Invoke($"[terminal write error] {ex.Message}\n");
        }
    }

    private static async Task StartReadLoop(Stream stream, Action<string> emit, CancellationToken ct)
    {
        // Use StreamReader to decode UTF-8 incrementally and emit as chunks
        using var reader = new StreamReader(stream, new UTF8Encoding(false, false), detectEncodingFromByteOrderMarks: true, bufferSize: 4096, leaveOpen: true);
        var buffer = new char[4096];
        try
        {
            while (!ct.IsCancellationRequested)
            {
                int read = await reader.ReadAsync(buffer.AsMemory(0, buffer.Length), ct).ConfigureAwait(false);
                if (read <= 0) break;
                emit(new string(buffer, 0, read));
            }
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
        catch (Exception ex)
        {
            emit($"[terminal error] {ex.Message}\n");
        }
    }

    public void Dispose()
    {
        Stop();
    }
}
