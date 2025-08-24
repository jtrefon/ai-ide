using Ide.Core.Events;
namespace ide;

public partial class MainPage : ContentPage
{
	int count = 0;

	public MainPage()
	{
		InitializeComponent();
	}

	private void OnCounterClicked(object? sender, EventArgs e)
	{
		count++;

		if (count == 1)
			CounterBtn.Text = $"Clicked {count} time";
		else
			CounterBtn.Text = $"Clicked {count} times";

		SemanticScreenReader.Announce(CounterBtn.Text);

		// Publish event to the in-process event bus
		var bus = ServiceLocator.GetRequiredService<IEventBus>();
		bus.Publish("ui.click", nameof(MainPage), new Dictionary<string, object?>
		{
			["control"] = "CounterBtn",
			["count"] = count
		});
	}
}
