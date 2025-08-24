using System.Collections.Immutable;

namespace Ide.Core.Events;

/// <summary>
/// Lock-free, immutable-list based event bus implementation.
/// </summary>
public sealed class EventBus : IEventBus
{
    private ImmutableList<Action<EventRecord>> _subscribers = ImmutableList<Action<EventRecord>>.Empty;

    public IDisposable Subscribe(Action<EventRecord> handler)
    {
        if (handler is null) throw new ArgumentNullException(nameof(handler));
        ImmutableInterlocked.Update(ref _subscribers, list => list.Add(handler));
        return new Unsubscriber(this, handler);
    }

    public void Publish(EventRecord record)
    {
        // Snapshot for consistent iteration
        var snapshot = _subscribers;
        foreach (var handler in snapshot)
        {
            try { handler(record); }
            catch { /* Swallow to preserve bus; consider logging in future */ }
        }
    }

    public void Publish(string type, string source, IReadOnlyDictionary<string, object?>? data = null)
    {
        Publish(EventFactory.Create(type, source, data));
    }

    private sealed class Unsubscriber : IDisposable
    {
        private EventBus? _bus;
        private readonly Action<EventRecord> _handler;

        public Unsubscriber(EventBus bus, Action<EventRecord> handler)
        {
            _bus = bus;
            _handler = handler;
        }

        public void Dispose()
        {
            var bus = Interlocked.Exchange(ref _bus, null);
            if (bus is null) return;
            ImmutableInterlocked.Update(ref bus._subscribers, list => list.Remove(_handler));
        }
    }
}
