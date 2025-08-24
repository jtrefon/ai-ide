using Ide.Core.Events;
using Ide.Core.Files;
using Ide.Core.Searching;
using Microsoft.Extensions.DependencyInjection;
using Ide.Core.State;

namespace Ide.Tests;

public class DependencyInjectionTests
{
    private static ServiceProvider BuildProvider()
    {
        var services = new ServiceCollection();
        services.AddSingleton<IEventBus, EventBus>();
        services.AddSingleton<IFileService, FileService>();
        services.AddSingleton<IBrowseService, BrowseService>();
        services.AddSingleton<ICodeSearchService, CodeSearchService>();
        services.AddSingleton<IStateStore, StateStore>();
        return services.BuildServiceProvider();
    }

    [Fact]
    public void CoreServicesResolve()
    {
        using var sp = BuildProvider();
        Assert.NotNull(sp.GetService<IEventBus>());
        Assert.NotNull(sp.GetService<IFileService>());
        Assert.NotNull(sp.GetService<IBrowseService>());
        Assert.NotNull(sp.GetService<ICodeSearchService>());
        Assert.NotNull(sp.GetService<IStateStore>());
    }
}
