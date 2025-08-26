using Microsoft.Maui.Controls.Xaml;

[assembly: XmlnsDefinition("http://schemas.microsoft.com/dotnet/maui/global", "ide")]
[assembly: XmlnsDefinition("http://schemas.microsoft.com/dotnet/maui/global", "ide.Pages")]

namespace ide;

public static class ServiceLocator
{
        public static IServiceProvider Services { get; private set; } = default!;

        public static void Init(IServiceProvider services)
        {
                Services = services;
        }
}
