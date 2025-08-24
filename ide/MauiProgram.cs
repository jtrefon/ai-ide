using Microsoft.Extensions.Logging;
using Ide.Core.Events;
using Microsoft.Extensions.DependencyInjection;

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

#if DEBUG
		builder.Logging.AddDebug();
#endif

		var app = builder.Build();

        // Expose service provider to XAML pages
        ServiceLocator.Services = app.Services;

		return app;
	}
}
