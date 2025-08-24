using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.FileSystemGlobbing;

namespace Ide.Core.Indexing;

public sealed class LexicalIndexer : IIndexer
{
    private readonly List<LineEntry> _entries = new();
    private readonly HashSet<string> _binaryExt = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png",".jpg",".jpeg",".gif",".bmp",".webp",".svg",".tiff",".ico",".heic",".heif",
        ".dll",".exe",".so",".dylib",".a",".lib",".pdf",".zip",".gz",".tar",".7z",".rar",
        ".mp3",".mp4",".mov",".avi",".mkv",".class",".jar",".wasm"
    };

    private const int MaxFileBytes = 2_000_000; // 2MB per file

    public void Dispose() => _entries.Clear();

    public async Task BuildAsync(string root, IEnumerable<string>? includeGlobs = null, IEnumerable<string>? excludeGlobs = null, CancellationToken ct = default)
    {
        _entries.Clear();
        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root)) return;
        var fullRoot = Path.GetFullPath(root);
        var include = BuildMatcher(includeGlobs);
        var exclude = BuildMatcher(excludeGlobs);
        foreach (var file in Directory.EnumerateFiles(fullRoot, "*", SearchOption.AllDirectories))
        {
            if (ct.IsCancellationRequested) break;
            var rel = Path.GetRelativePath(fullRoot, file).Replace('\\', '/');
            if (!IsIncluded(rel, include, exclude)) continue;
            if (await ShouldSkipFileAsync(file, ct).ConfigureAwait(false)) continue;
            await IndexFileAsync(file, ct).ConfigureAwait(false);
        }
    }

    internal static Matcher? BuildMatcher(IEnumerable<string>? globs)
    {
        if (globs == null) return null;
        var m = new Matcher(StringComparison.OrdinalIgnoreCase);
        foreach (var g in globs)
        {
            if (!string.IsNullOrWhiteSpace(g)) m.AddInclude(g);
        }
        return m;
    }

    internal static bool IsIncluded(string rel, Matcher? include, Matcher? exclude)
    {
        if (exclude != null && exclude.Match(rel).HasMatches) return false;
        if (include == null) return true;
        return include.Match(rel).HasMatches;
    }

    internal async Task<bool> ShouldSkipFileAsync(string file, CancellationToken ct)
    {
        var ext = Path.GetExtension(file);
        if (!string.IsNullOrEmpty(ext) && _binaryExt.Contains(ext)) return true;
        FileInfo fi; try { fi = new FileInfo(file); } catch { return true; }
        if (fi.Length > MaxFileBytes) return true;
        int sniff = (int)Math.Min(8192, fi.Length);
        if (sniff > 0)
        {
            var buf = ArrayPool<byte>.Shared.Rent(sniff);
            try
            {
                using var fs = File.OpenRead(file);
                int read = await fs.ReadAsync(buf.AsMemory(0, sniff), ct).ConfigureAwait(false);
                for (int i = 0; i < read; i++) if (buf[i] == 0) return true;
            }
            catch { return true; }
            finally { ArrayPool<byte>.Shared.Return(buf); }
        }
        return false;
    }

    internal async Task<int> IndexFileAsync(string file, CancellationToken ct)
    {
        try
        {
            var lines = await File.ReadAllLinesAsync(file, Encoding.UTF8, ct).ConfigureAwait(false);
            int count = 0;
            for (int i = 0; i < lines.Length && !ct.IsCancellationRequested; i++)
            {
                var preview = lines[i];
                _entries.Add(new LineEntry(file, i + 1, preview, preview.ToLowerInvariant()));
                count++;
            }
            return count;
        }
        catch { return 0; }
    }

    public Task<IReadOnlyList<IndexedMatch>> QueryAsync(string token, int limit = 100, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(token)) return Task.FromResult<IReadOnlyList<IndexedMatch>>(Array.Empty<IndexedMatch>());
        var needle = token.ToLowerInvariant();
        var results = new List<IndexedMatch>(Math.Min(limit, 128));
        foreach (var e in _entries)
        {
            if (ct.IsCancellationRequested) break;
            if (e.PreviewLower.Contains(needle))
            {
                results.Add(new IndexedMatch(e.File, e.Line, e.Preview));
                if (results.Count >= limit) break;
            }
        }
        return Task.FromResult<IReadOnlyList<IndexedMatch>>(results);
    }

    private readonly record struct LineEntry(string File, int Line, string Preview, string PreviewLower);
}
