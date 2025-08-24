using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.FileSystemGlobbing;

namespace Ide.Core.Files;

public sealed class BrowseService : IBrowseService
{
    public Task<IReadOnlyList<BrowseEntry>> BrowseAsync(
        string root,
        IEnumerable<string>? includeGlobs = null,
        IEnumerable<string>? excludeGlobs = null,
        int? maxDepth = null,
        int? maxEntries = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(root)) throw new ArgumentException("Root required", nameof(root));
        var fullRoot = Path.GetFullPath(root);
        int depthCap = maxDepth ?? int.MaxValue;
        int entryCap = Math.Max(0, maxEntries ?? int.MaxValue);

        var includeMatcher = new Matcher(StringComparison.OrdinalIgnoreCase);
        bool hasIncludes = false;
        if (includeGlobs != null)
        {
            foreach (var g in includeGlobs)
            {
                if (string.IsNullOrWhiteSpace(g)) continue;
                includeMatcher.AddInclude(g);
                hasIncludes = true;
            }
        }

        var excludeMatcher = new Matcher(StringComparison.OrdinalIgnoreCase);
        bool hasExcludes = false;
        if (excludeGlobs != null)
        {
            foreach (var g in excludeGlobs)
            {
                if (string.IsNullOrWhiteSpace(g)) continue;
                excludeMatcher.AddInclude(g);
                hasExcludes = true;
            }
        }

        bool IsIncluded(string rel)
        {
            if (hasExcludes && excludeMatcher.Match(rel).HasMatches) return false;
            if (!hasIncludes) return true; // include all by default
            return includeMatcher.Match(rel).HasMatches;
        }

        var results = new List<BrowseEntry>(Math.Min(entryCap, 1024));
        var stack = new Stack<(string dir, int depth)>();
        stack.Push((fullRoot, 0));

        while (stack.Count > 0)
        {
            if (ct.IsCancellationRequested) break;
            var (dir, depth) = stack.Pop();
            if (depth > depthCap) continue;

            IEnumerable<string> dirs = Array.Empty<string>();
            IEnumerable<string> files = Array.Empty<string>();
            try
            {
                dirs = Directory.EnumerateDirectories(dir);
            }
            catch { }
            try
            {
                files = Directory.EnumerateFiles(dir);
            }
            catch { }

            foreach (var d in dirs)
            {
                var rel = Path.GetRelativePath(fullRoot, d).Replace('\\', '/');
                // If directory is excluded, prune traversal
                if (hasExcludes && excludeMatcher.Match(rel + "/").HasMatches)
                {
                    continue;
                }

                // Add directory entry if it passes include filter
                if (IsIncluded(rel))
                {
                    results.Add(new BrowseEntry(Path.Combine(root, rel), true, null));
                    if (results.Count >= entryCap) goto Done;
                }
                // Traverse deeper if allowed
                if (depth + 1 <= depthCap)
                {
                    stack.Push((d, depth + 1));
                }
            }

            foreach (var f in files)
            {
                var rel = Path.GetRelativePath(fullRoot, f).Replace('\\', '/');
                if (!IsIncluded(rel)) continue;
                long size = 0;
                try { size = new FileInfo(f).Length; } catch { }
                results.Add(new BrowseEntry(Path.Combine(root, rel), false, size));
                if (results.Count >= entryCap) goto Done;
            }
        }

    Done:
        return Task.FromResult<IReadOnlyList<BrowseEntry>>(results);
    }
}
