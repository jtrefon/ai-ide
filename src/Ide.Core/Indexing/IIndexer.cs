using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Ide.Core.Indexing;

public sealed record IndexedMatch(string File, int Line, string Preview);

public interface IIndexer : IDisposable
{
    /// <summary>
    /// Build or rebuild the lexical index for a root with optional globs.
    /// </summary>
    Task BuildAsync(
        string root,
        IEnumerable<string>? includeGlobs = null,
        IEnumerable<string>? excludeGlobs = null,
        CancellationToken ct = default);

    /// <summary>
    /// Query the index for a token (case-insensitive). Returns distinct file+line matches up to 'limit'.
    /// </summary>
    Task<IReadOnlyList<IndexedMatch>> QueryAsync(
        string token,
        int limit = 100,
        CancellationToken ct = default);
}
