using Ide.Core.Events;

namespace Ide.Tests;

public class EventBusTests
{
    [Fact]
    public void Publish_Delivers_To_Subscriber()
    {
        var bus = new EventBus();
        EventRecord? got = null;
        using var _ = bus.Subscribe(e => got = e);

        var rec = EventFactory.Create("test.event", "unit");
        bus.Publish(rec);

        Assert.NotNull(got);
        Assert.Equal(rec, got);
    }

    [Fact]
    public void Dispose_Unsubscribes()
    {
        var bus = new EventBus();
        int count = 0;
        var sub = bus.Subscribe(_ => count++);
        sub.Dispose();

        bus.Publish("a", "b");
        Assert.Equal(0, count);
    }

    [Fact]
    public void Multiple_Subscribers_All_Receive()
    {
        var bus = new EventBus();
        int a = 0, b = 0;
        using var _1 = bus.Subscribe(_ => a++);
        using var _2 = bus.Subscribe(_ => b++);

        bus.Publish("x", "y");
        Assert.Equal(1, a);
        Assert.Equal(1, b);
    }
}
