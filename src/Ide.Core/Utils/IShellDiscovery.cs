namespace Ide.Core.Utils;

public sealed record ShellInfo(string FileName, IReadOnlyList<string> Arguments);

public interface IShellDiscovery
{
    bool IsWindows { get; }
    ShellInfo GetShell();
}
