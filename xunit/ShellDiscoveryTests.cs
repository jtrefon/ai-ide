using Ide.Core.Utils;

namespace Ide.Tests;

public class ShellDiscoveryTests
{
    [Fact]
    public void WindowsPrefersPowerShell()
    {
        var discovery = new ShellDiscovery(p => p.Contains("powershell.exe"), isWindows: true);
        var shell = discovery.GetShell();
        Assert.Contains("powershell.exe", shell.FileName);
        Assert.True(discovery.IsWindows);
    }

    [Fact]
    public void UnixFallsBackToZsh()
    {
        var discovery = new ShellDiscovery(p => p == "/bin/zsh", isWindows: false);
        var shell = discovery.GetShell();
        Assert.Equal("/bin/zsh", shell.FileName);
        Assert.False(discovery.IsWindows);
    }
}
