using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Ide.Core.Searching;

public enum SearchKind
{
    Literal,
    Regex
}

public sealed record SearchMatch(string File, int Line, string Preview);

public interface ICodeSearchService
{
    /// <summary>
    /// Search files under the given root.
    /// </summary>
    /// <param name="root">Root directory to search.</param>
    /// <param name="query">Text or regex to search for.</param>
    /// <param name="kind">Literal or Regex search.</param>
    /// <param name="includeGlobs">Optional include globs (e.g., "**/*.cs"). If null, includes all.</param>
    /// <param name="excludeGlobs">Optional exclude globs (e.g., "**/bin/**").</param>
    /// <param name="limit">Max number of matches to return.</param>
    /// <param name="ct">Cancellation token.</param>
    Task<IReadOnlyList<SearchMatch>> SearchAsync(
        string root,
        string query,
        SearchKind kind,
        IEnumerable<string>? includeGlobs = null,
        IEnumerable<string>? excludeGlobs = null,
        int limit = 200,
        CancellationToken ct = default);
}
