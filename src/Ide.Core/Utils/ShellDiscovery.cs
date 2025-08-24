using System;
using System.IO;
using System.Collections.Generic;

namespace Ide.Core.Utils;

public sealed class ShellDiscovery : IShellDiscovery
{
    private readonly Func<string, bool> _fileExists;
    private readonly bool _isWindows;

    public ShellDiscovery(Func<string, bool>? fileExists = null, bool? isWindows = null)
    {
        _fileExists = fileExists ?? File.Exists;
        _isWindows = isWindows ?? OperatingSystem.IsWindows();
    }

    public bool IsWindows => _isWindows;

    public ShellInfo GetShell() => IsWindows ? GetWindowsShell() : GetUnixShell();

    private ShellInfo GetWindowsShell()
    {
        var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        var pwsh = Path.Combine(system, "WindowsPowerShell", "v1.0", "powershell.exe");
        if (_fileExists(pwsh))
        {
            return new ShellInfo(pwsh, new[] { "-NoLogo", "-NoProfile" });
        }
        var cmd = Environment.GetEnvironmentVariable("ComSpec") ?? Path.Combine(system, "cmd.exe");
        return new ShellInfo(cmd, Array.Empty<string>());
    }

    private ShellInfo GetUnixShell()
    {
        var shell = _fileExists("/bin/zsh") ? "/bin/zsh" : (_fileExists("/bin/bash") ? "/bin/bash" : "/bin/sh");
        bool isZsh = shell.EndsWith("/zsh", StringComparison.Ordinal);
        bool isBash = shell.EndsWith("/bash", StringComparison.Ordinal);
        bool useScript = _fileExists("/usr/bin/script");
        var args = new List<string>();
        if (useScript)
        {
            args.Add("-q");
            args.Add("/dev/null");
            args.Add(shell);
            if (isZsh)
            {
                args.Add("-f");
                args.Add("-i");
            }
            else if (isBash)
            {
                args.Add("--noprofile");
                args.Add("--norc");
                args.Add("-i");
            }
            else
            {
                args.Add("-i");
            }
            return new ShellInfo("/usr/bin/script", args);
        }
        if (isZsh)
        {
            args.Add("-f");
            args.Add("-i");
        }
        else if (isBash)
        {
            args.Add("--noprofile");
            args.Add("--norc");
            args.Add("-i");
        }
        else
        {
            args.Add("-i");
        }
        return new ShellInfo(shell, args);
    }
}
