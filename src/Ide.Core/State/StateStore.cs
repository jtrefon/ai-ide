using System.Collections.Generic;
using System.Collections.Immutable;

namespace Ide.Core.State;

/// <summary>
/// Thread-safe in-memory state store using immutable dictionaries.
/// </summary>
public sealed class StateStore : IStateStore
{
    private ImmutableDictionary<string, object?> _state = ImmutableDictionary<string, object?>.Empty;

    public void Set<T>(string key, T value)
    {
        if (key is null) throw new ArgumentNullException(nameof(key));
        ImmutableInterlocked.Update(ref _state, s => s.SetItem(key, value));
    }

    public bool TryGet<T>(string key, out T? value)
    {
        if (key is null) throw new ArgumentNullException(nameof(key));
        if (_state.TryGetValue(key, out var v) && v is T t)
        {
            value = t;
            return true;
        }
        value = default;
        return false;
    }

    public IReadOnlyDictionary<string, object?> Snapshot() => _state;

    public void Restore(IReadOnlyDictionary<string, object?> snapshot)
    {
        if (snapshot is null) throw new ArgumentNullException(nameof(snapshot));
        var imm = snapshot as ImmutableDictionary<string, object?>
            ?? ImmutableDictionary.CreateRange(snapshot);
        Interlocked.Exchange(ref _state, imm);
    }
}
