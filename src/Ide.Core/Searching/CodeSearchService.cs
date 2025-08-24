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
        if (string.IsNullOrEmpty(query)) return Array.Empty<SearchMatch>();
        if (limit <= 0) return Array.Empty<SearchMatch>();

        var matcher = new Matcher(StringComparison.OrdinalIgnoreCase);
        var includes = includeGlobs?.ToArray();
        if (includes == null || includes.Length == 0)
        {
            matcher.AddInclude("**/*");
        }
        else
        {
            matcher.AddIncludePatterns(includes);
        }

        // Exclude defaults + user ones
        var excludes = (excludeGlobs ?? Array.Empty<string>()).Concat(DefaultExclude).ToArray();
        if (excludes.Length > 0) matcher.AddExcludePatterns(excludes);

        var dirInfo = new DirectoryInfo(root);
        var dirWrapper = new DirectoryInfoWrapper(dirInfo);
        var result = matcher.Execute(dirWrapper);

        var matches = new ConcurrentBag<SearchMatch>();
        int maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

        // Prepare search function
        Func<string, Task> processFile = async path =>
        {
            if (matches.Count >= limit) return;
            if (ct.IsCancellationRequested) return;

            var ext = Path.GetExtension(path);
            if (BinaryExtensions.Contains(ext)) return;

            FileInfo fi;
            try { fi = new FileInfo(path); }
            catch { return; }
            if (!fi.Exists) return;
            if (fi.Length <= 0) return; // skip empty
            if (fi.Length > maxFileSizeBytes) return;

            // Binary sniff: any NUL bytes in first 4KB
            try
            {
                using var fs = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                var probe = new byte[Math.Min(4096, (int)Math.Min(fi.Length, int.MaxValue))];
                int read = await fs.ReadAsync(probe, 0, probe.Length, ct).ConfigureAwait(false);
                for (int i = 0; i < read; i++)
                {
                    if (probe[i] == 0) return; // binary
                }
            }
            catch { return; }

            // Read lines
            string[] lines;
            try
            {
                lines = await File.ReadAllLinesAsync(path, Encoding.UTF8, ct).ConfigureAwait(false);
            }
            catch
            {
                // If not UTF-8, skip
                return;
            }

            Regex? rx = null;
            if (kind == SearchKind.Regex)
            {
                try { rx = new Regex(query, RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.Multiline); }
                catch { return; }
            }

            for (int i = 0; i < lines.Length; i++)
            {
                if (matches.Count >= limit) break;
                if (ct.IsCancellationRequested) break;

                var line = lines[i];

                if (kind == SearchKind.Literal)
                {
                    int start = 0;
                    while (start <= line.Length - query.Length && matches.Count < limit)
                    {
                        int idx = line.IndexOf(query, start, StringComparison.OrdinalIgnoreCase);
                        if (idx < 0) break;
                        string preview = line.Length > 200 ? line[..200] : line;
                        matches.Add(new SearchMatch(NormalizePath(path, root), i + 1, preview));
                        start = idx + Math.Max(1, query.Length);
                    }
                }
                else
                {
                    var col = rx!.Matches(line);
                    if (col.Count > 0)
                    {
                        string preview = line.Length > 200 ? line[..200] : line;
                        foreach (Match m in col)
                        {
                            if (matches.Count >= limit) break;
                            matches.Add(new SearchMatch(NormalizePath(path, root), i + 1, preview));
                        }
                    }
                }
            }
        };

        // Process files (sequential to keep it simple; can be parallelized later)
        foreach (var file in result.Files)
        {
            var fullPath = Path.Combine(root, file.Path);
            await processFile(fullPath).ConfigureAwait(false);
            if (matches.Count >= limit) break;
        }

        return matches.Take(limit).ToList();
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
