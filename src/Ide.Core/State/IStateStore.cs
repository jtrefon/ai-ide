using System.Collections.Generic;

namespace Ide.Core.State;

/// <summary>
/// Provides typed access to application state.
/// </summary>
public interface IStateStore
{
    /// <summary>
    /// Store a value under the specified key.
    /// </summary>
    /// <typeparam name="T">Value type.</typeparam>
    /// <param name="key">State key.</param>
    /// <param name="value">Value to store.</param>
    void Set<T>(string key, T value);

    /// <summary>
    /// Try to retrieve a value by key.
    /// </summary>
    /// <typeparam name="T">Expected type.</typeparam>
    /// <param name="key">State key.</param>
    /// <param name="value">Output value if found.</param>
    /// <returns>True if key exists and value is of type T.</returns>
    bool TryGet<T>(string key, out T? value);

    /// <summary>
    /// Get an immutable snapshot of current state.
    /// </summary>
    IReadOnlyDictionary<string, object?> Snapshot();

    /// <summary>
    /// Replace the store with a snapshot.
    /// </summary>
    /// <param name="snapshot">Snapshot to restore.</param>
    void Restore(IReadOnlyDictionary<string, object?> snapshot);
}
