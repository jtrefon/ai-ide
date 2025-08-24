namespace Ide.Core.Events;

/// <summary>
/// Immutable, structured event record carried over the in-process event bus.
/// </summary>
/// <param name="Id">Deterministic or random correlation id for the event.</param>
/// <param name="Timestamp">UTC timestamp when the event was created.</param>
/// <param name="Type">Short machine name like "ui.click" or "agent.plan".</param>
/// <param name="Source">Component or class that produced the event.</param>
/// <param name="Data">Optional structured payload (kept small by policy).</param>
public sealed record EventRecord(
    Guid Id,
    DateTimeOffset Timestamp,
    string Type,
    string Source,
    IReadOnlyDictionary<string, object?>? Data
);
