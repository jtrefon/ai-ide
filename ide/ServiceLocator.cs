using Microsoft.Extensions.DependencyInjection;

namespace ide;

/// <summary>
/// Temporary service locator for pages created via XAML without DI.
/// </summary>
public static class ServiceLocator
{
    public static IServiceProvider Services { get; internal set; } = default!;

    public static T GetRequiredService<T>() where T : notnull => Services.GetRequiredService<T>();
}
