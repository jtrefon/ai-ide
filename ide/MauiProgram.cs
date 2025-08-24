using Microsoft.Extensions.Logging;
using Ide.Core.Events;
using Microsoft.Extensions.DependencyInjection;
using Ide.Core.Utils;
using Ide.Core.Files;
using Ide.Core.Searching;
using Ide.Core.Vcs;
using Ide.Core.Indexing;

namespace ide;

public static class MauiProgram
{
	public static MauiApp CreateMauiApp()
	{
		var builder = MauiApp.CreateBuilder();
		builder
			.UseMauiApp<App>()
			.ConfigureFonts(fonts =>
			{
				fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
				fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
			});

        // Core services
        builder.Services.AddSingleton<IEventBus, EventBus>();
        builder.Services.AddSingleton<IRunner, Runner>();
        builder.Services.AddSingleton<IFileService, FileService>();
        builder.Services.AddSingleton<ICodeSearchService, CodeSearchService>();
        builder.Services.AddSingleton<IBrowseService, BrowseService>();
        builder.Services.AddSingleton<IGitService, GitService>();
        builder.Services.AddSingleton<IIndexer, LexicalIndexer>();
        builder.Services.AddSingleton<IShellDiscovery, ShellDiscovery>();
        builder.Services.AddSingleton<ITerminalBackend>(sp =>
        {
                var sd = sp.GetRequiredService<IShellDiscovery>();
                return sd.IsWindows
                        ? new WindowsTerminalBackend(sd)
                        : new ScriptTerminalBackend(sd);
        });

        // Pages
        builder.Services.AddSingleton<AppShell>();
        builder.Services.AddTransient<MainPage>();
        builder.Services.AddTransient<AgentPage>();

#if DEBUG
		builder.Logging.AddDebug();
#endif

                return builder.Build();
        }
}
