using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Ide.Core.Files;

public sealed record BrowseEntry(string Path, bool IsDirectory, long? SizeBytes);

public interface IBrowseService
{
    /// <summary>
    /// Enumerate a tree under root with optional include/exclude globs, max depth, and entry cap.
    /// </summary>
    Task<IReadOnlyList<BrowseEntry>> BrowseAsync(
        string root,
        IEnumerable<string>? includeGlobs = null,
        IEnumerable<string>? excludeGlobs = null,
        int? maxDepth = null,
        int? maxEntries = null,
        CancellationToken ct = default);
}
