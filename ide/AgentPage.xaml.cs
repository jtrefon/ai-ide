using System.Collections.ObjectModel;
using Ide.Core.Events;
using Ide.Core.Searching;
using Microsoft.Extensions.DependencyInjection;

namespace ide;

public partial class AgentPage : ContentPage
{
    private readonly ObservableCollection<EventRecord> _events = new();
    private readonly ObservableCollection<SearchMatch> _searchResults = new();
    private IDisposable? _subscription;
    private readonly IEventBus _eventBus;
    private readonly ICodeSearchService _searchService;

    public AgentPage(IEventBus eventBus, ICodeSearchService searchService)
    {
        InitializeComponent();
        EventsView.ItemsSource = _events;
        SearchResultsView.ItemsSource = _searchResults;
        _eventBus = eventBus;
        _searchService = searchService;
        // Best-effort: prefill root with current directory if accessible
        try { RootEntry.Text = Environment.CurrentDirectory; } catch { }
    }

    public static AgentPage Create() => App.Current.Services.GetRequiredService<AgentPage>();

    protected override void OnAppearing()
    {
        base.OnAppearing();
        _subscription = _eventBus.Subscribe(e => MainThread.BeginInvokeOnMainThread(() => _events.Insert(0, e)));
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _subscription?.Dispose();
        _subscription = null;
    }

    private void OnPublishClicked(object? sender, EventArgs e)
    {
        _eventBus.Publish("ui.click", nameof(AgentPage), new Dictionary<string, object?>
        {
            ["button"] = "Publish Test Event",
            ["ts"] = DateTimeOffset.UtcNow
        });
    }

    private async void OnSearchClicked(object? sender, EventArgs e)
    {
        var root = RootEntry.Text?.Trim();
        var query = QueryEntry.Text?.Trim();
        if (string.IsNullOrWhiteSpace(root) || string.IsNullOrWhiteSpace(query))
        {
            await DisplayAlert("Search", "Enter a root path and query.", "OK");
            return;
        }

        try
        {
            var results = await _searchService.SearchAsync(root, query, SearchKind.Literal, limit: 200);
            _searchResults.Clear();
            foreach (var r in results) _searchResults.Add(r);
        }
        catch (Exception ex)
        {
            await DisplayAlert("Search error", ex.Message, "OK");
        }
    }
}

