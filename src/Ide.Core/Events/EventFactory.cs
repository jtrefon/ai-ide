namespace Ide.Core.Events;

/// <summary>
/// Helpers to construct <see cref="EventRecord"/> instances.
/// </summary>
public static class EventFactory
{
    public static EventRecord Create(string type, string source, IReadOnlyDictionary<string, object?>? data = null)
        => new(
            Id: Guid.NewGuid(),
            Timestamp: DateTimeOffset.UtcNow,
            Type: type,
            Source: source,
            Data: data
        );
}
