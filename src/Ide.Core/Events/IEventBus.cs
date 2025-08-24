using System.Collections.Concurrent;

namespace Ide.Core.Events;

/// <summary>
/// Minimal in-process event bus for structured events.
/// Thread-safe, supports subscribe/unsubscribe and broadcast publish.
/// </summary>
public interface IEventBus
{
    /// <summary>
    /// Subscribe to all events. Returns an <see cref="IDisposable"/> to unsubscribe.
    /// </summary>
    /// <param name="handler">Handler invoked for each published event.</param>
    /// <returns>Disposable subscription token.</returns>
    IDisposable Subscribe(Action<EventRecord> handler);

    /// <summary>
    /// Publish a pre-constructed event.
    /// </summary>
    void Publish(EventRecord record);

    /// <summary>
    /// Convenience publish with parts.
    /// </summary>
    void Publish(string type, string source, IReadOnlyDictionary<string, object?>? data = null);
}
