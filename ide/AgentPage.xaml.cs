using System.Collections.ObjectModel;
using Ide.Core.Events;

namespace ide;

public partial class AgentPage : ContentPage
{
    private readonly ObservableCollection<EventRecord> _events = new();
    private IDisposable? _subscription;

    public AgentPage()
    {
        InitializeComponent();
        EventsView.ItemsSource = _events;
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        var bus = ServiceLocator.GetRequiredService<IEventBus>();
        _subscription = bus.Subscribe(e => MainThread.BeginInvokeOnMainThread(() => _events.Insert(0, e)));
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _subscription?.Dispose();
        _subscription = null;
    }

    private void OnPublishClicked(object? sender, EventArgs e)
    {
        var bus = ServiceLocator.GetRequiredService<IEventBus>();
        bus.Publish("ui.click", nameof(AgentPage), new Dictionary<string, object?>
        {
            ["button"] = "Publish Test Event",
            ["ts"] = DateTimeOffset.UtcNow
        });
    }
}
