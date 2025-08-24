using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Text.RegularExpressions;
using Ide.Core.Utils;

namespace ide;

public sealed class WindowsTerminalBackend : ITerminalBackend
{
    public event Action<string>? Output;
    public event Action<string>? Error;

    private readonly IShellDiscovery _shellDiscovery;
    private Process? _proc;
    private StreamWriter? _stdin;
    private CancellationTokenSource? _cts;

    public WindowsTerminalBackend(IShellDiscovery shellDiscovery)
    {
        _shellDiscovery = shellDiscovery;
    }

    public bool IsRunning => _proc is { HasExited: false };

    public void Start()
    {
        if (IsRunning) return;
        var shell = _shellDiscovery.GetShell();
        var psi = new ProcessStartInfo
        {
            FileName = shell.FileName,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Environment.CurrentDirectory,
        };
        psi.Environment["TERM"] = "xterm";
        psi.Environment["PROMPT"] = "$ ";
        psi.Environment["NO_COLOR"] = "1";
        foreach (var arg in shell.Arguments)
        {
            psi.ArgumentList.Add(arg);
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

    private static readonly Regex AnsiCsi = new("\u001B\\[[0-9;?]*[ -/]*[@-~]", RegexOptions.Compiled);
    private static readonly Regex AnsiOsc = new("\u001B\u005D[^\u0007]*\u0007", RegexOptions.Compiled);
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
