using System.Collections.Concurrent;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Extensions.FileSystemGlobbing;
using Microsoft.Extensions.FileSystemGlobbing.Abstractions;

namespace Ide.Core.Searching;

public sealed class CodeSearchService : ICodeSearchService
{
    private static readonly string[] DefaultExclude = new[]
    {
        "**/bin/**", "**/obj/**", "**/.git/**", "**/.vs/**", "**/.idea/**", "**/.vscode/**",
        "**/TestResults/**", "**/artifacts/**", "**/node_modules/**"
    };

    private static readonly HashSet<string> BinaryExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".dll", ".exe", ".so", ".dylib", ".a", ".zip", ".7z", ".rar", ".gz", ".tar",
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".pdf", ".nupkg", ".snupkg",
        ".apk", ".aab", ".ipa"
    };

    public async Task<IReadOnlyList<SearchMatch>> SearchAsync(
        string root,
        string query,
        SearchKind kind,
        IEnumerable<string>? includeGlobs = null,
        IEnumerable<string>? excludeGlobs = null,
        int limit = 200,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(root)) throw new ArgumentException("Root directory is required", nameof(root));
        if (!Directory.Exists(root)) throw new DirectoryNotFoundException(root);
        if (string.IsNullOrEmpty(query) || limit <= 0) return Array.Empty<SearchMatch>();

        var matcher = BuildMatcher(includeGlobs, excludeGlobs);
        var result = matcher.Execute(new DirectoryInfoWrapper(new DirectoryInfo(root)));
        var matches = new ConcurrentBag<SearchMatch>();
        foreach (var file in result.Files)
        {
            if (matches.Count >= limit || ct.IsCancellationRequested) break;
            var fullPath = Path.Combine(root, file.Path);
            if (await ShouldSkipFileAsync(fullPath, ct).ConfigureAwait(false)) continue;
            await SearchFileAsync(fullPath, root, query, kind, limit, matches, ct).ConfigureAwait(false);
        }
        return matches.Take(limit).ToList();
    }

    internal static Matcher BuildMatcher(IEnumerable<string>? includeGlobs, IEnumerable<string>? excludeGlobs)
    {
        var m = new Matcher(StringComparison.OrdinalIgnoreCase);
        var includes = includeGlobs?.ToArray();
        if (includes == null || includes.Length == 0) m.AddInclude("**/*"); else m.AddIncludePatterns(includes);
        var excludes = (excludeGlobs ?? Array.Empty<string>()).Concat(DefaultExclude).ToArray();
        if (excludes.Length > 0) m.AddExcludePatterns(excludes);
        return m;
    }

    internal static async Task<bool> ShouldSkipFileAsync(string path, CancellationToken ct)
    {
        var ext = Path.GetExtension(path);
        if (BinaryExtensions.Contains(ext)) return true;
        FileInfo fi; try { fi = new FileInfo(path); } catch { return true; }
        if (!fi.Exists || fi.Length <= 0 || fi.Length > 5 * 1024 * 1024) return true;
        var probe = new byte[Math.Min(4096, (int)Math.Min(fi.Length, int.MaxValue))];
        try
        {
            using var fs = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            int read = await fs.ReadAsync(probe, 0, probe.Length, ct).ConfigureAwait(false);
            for (int i = 0; i < read; i++) if (probe[i] == 0) return true;
        }
        catch { return true; }
        return false;
    }

    internal static async Task SearchFileAsync(string path, string root, string query, SearchKind kind, int limit, ConcurrentBag<SearchMatch> matches, CancellationToken ct)
    {
        string[] lines;
        try { lines = await File.ReadAllLinesAsync(path, Encoding.UTF8, ct).ConfigureAwait(false); }
        catch { return; }
        Regex? rx = kind == SearchKind.Regex ? CreateRegex(query) : null;
        for (int i = 0; i < lines.Length && matches.Count < limit && !ct.IsCancellationRequested; i++)
        {
            var line = lines[i];
            if (kind == SearchKind.Literal) MatchLiteral(line, query, path, root, i, limit, matches);
            else if (rx != null) MatchRegex(line, rx, path, root, i, limit, matches);
        }
    }

    internal static Regex? CreateRegex(string query)
    {
        try { return new Regex(query, RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.Multiline); }
        catch { return null; }
    }

    internal static void MatchLiteral(string line, string query, string path, string root, int index, int limit, ConcurrentBag<SearchMatch> matches)
    {
        int start = 0;
        while (start <= line.Length - query.Length && matches.Count < limit)
        {
            int idx = line.IndexOf(query, start, StringComparison.OrdinalIgnoreCase);
            if (idx < 0) break;
            AddMatch(matches, path, root, index, line);
            start = idx + Math.Max(1, query.Length);
        }
    }

    internal static void MatchRegex(string line, Regex rx, string path, string root, int index, int limit, ConcurrentBag<SearchMatch> matches)
    {
        foreach (Match _ in rx.Matches(line))
        {
            if (matches.Count >= limit) break;
            AddMatch(matches, path, root, index, line);
        }
    }

    internal static void AddMatch(ConcurrentBag<SearchMatch> matches, string path, string root, int index, string line)
    {
        string preview = line.Length > 200 ? line[..200] : line;
        matches.Add(new SearchMatch(NormalizePath(path, root), index + 1, preview));
    }

    private static string NormalizePath(string path, string root)
    {
        try
        {
            var full = Path.GetFullPath(path);
            var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (full.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
            {
                var rel = full.Substring(fullRoot.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                return rel.Replace(Path.DirectorySeparatorChar, '/');
            }
            return full.Replace(Path.DirectorySeparatorChar, '/');
        }
        catch
        {
            return path.Replace(Path.DirectorySeparatorChar, '/');
        }
    }
}
