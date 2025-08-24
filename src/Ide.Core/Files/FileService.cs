using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Ide.Core.Utils;

namespace Ide.Core.Files;

public sealed class FileService : IFileService
{
    private const int DefaultMaxBytes = 1_000_000; // 1 MB per file for read

    public async Task<IReadOnlyList<ReadResult>> ReadFilesAsync(
        IEnumerable<string> files,
        int? maxBytes = null,
        CancellationToken ct = default)
    {
        int cap = maxBytes ?? DefaultMaxBytes;
        var results = new List<ReadResult>();
        foreach (var path in files)
        {
            if (ct.IsCancellationRequested) break;
            results.Add(await ReadFileAsync(path, cap, ct).ConfigureAwait(false));
        }
        return results;
    }

    public async Task<IReadOnlyList<WriteResult>> WriteFilesAsync(
        IEnumerable<FileWrite> writes,
        bool atomic = true,
        CancellationToken ct = default)
    {
        var results = new List<WriteResult>();
        foreach (var w in writes)
        {
            if (ct.IsCancellationRequested) break;
            results.Add(await WriteFileAsync(w, atomic, ct).ConfigureAwait(false));
        }
        return results;
    }

    public async Task<PatchResult> ApplyUnifiedDiffAsync(string repoRoot, string diff, bool atomic = true, CancellationToken ct = default)
    {
        try
        {
            var patches = ParseDiffLines(repoRoot, diff).ToList();
            int changed = 0;
            foreach (var fp in patches)
            {
                if (ct.IsCancellationRequested) break;
                var original = File.Exists(fp.File)
                    ? await File.ReadAllTextAsync(fp.File, Encoding.UTF8, ct).ConfigureAwait(false)
                    : string.Empty;
                var newContent = DiffHelper.ApplyHunks(original, fp.Hunks);
                if (newContent == null)
                    return new PatchResult(false, changed, $"Failed to apply hunks for {fp.File}");
                if (atomic)
                    await WriteFileAtomicAsync(fp.File, newContent, ct).ConfigureAwait(false);
                else
                    await File.WriteAllTextAsync(fp.File, newContent, new UTF8Encoding(false), ct).ConfigureAwait(false);
                changed++;
            }
            return new PatchResult(true, changed, null);
        }
        catch (Exception ex)
        {
            return new PatchResult(false, 0, ex.Message);
        }
    }

    internal static async Task<ReadResult> ReadFileAsync(string path, int cap, CancellationToken ct)
    {
        try
        {
            if (!File.Exists(path)) return new ReadResult(path, false, null, "Not found");
            var info = new FileInfo(path);
            if (info.Length > cap) return new ReadResult(path, false, null, $"File exceeds cap {cap} bytes");
            if (await IsBinaryAsync(path, (int)Math.Min(8192, info.Length), ct).ConfigureAwait(false))
                return new ReadResult(path, false, null, "Binary detected");
            var text = await File.ReadAllTextAsync(path, Encoding.UTF8, ct).ConfigureAwait(false);
            return new ReadResult(path, true, text, null);
        }
        catch (Exception ex)
        {
            return new ReadResult(path, false, null, ex.Message);
        }
    }

    internal static async Task<WriteResult> WriteFileAsync(FileWrite w, bool atomic, CancellationToken ct)
    {
        try
        {
            if (w.Content.IndexOf('\0') >= 0)
                return new WriteResult(w.Path, false, "Binary content (NUL) not allowed");
            var dir = Path.GetDirectoryName(w.Path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            if (atomic)
                await WriteFileAtomicAsync(w.Path, w.Content, ct).ConfigureAwait(false);
            else
                await File.WriteAllTextAsync(w.Path, w.Content, new UTF8Encoding(false), ct).ConfigureAwait(false);
            return new WriteResult(w.Path, true, null);
        }
        catch (Exception ex)
        {
            return new WriteResult(w.Path, false, ex.Message);
        }
    }

    internal static async Task WriteFileAtomicAsync(string path, string content, CancellationToken ct)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = path + ".tmp-" + Guid.NewGuid().ToString("N");
        await File.WriteAllTextAsync(tmp, content, new UTF8Encoding(false), ct).ConfigureAwait(false);
        if (File.Exists(path)) File.Replace(tmp, path, null, true); else File.Move(tmp, path);
    }

    internal static async Task<bool> IsBinaryAsync(string path, int sniffBytes, CancellationToken ct)
    {
        var ext = Path.GetExtension(path);
        if (!string.IsNullOrEmpty(ext) && BinaryExtensions.Set.Contains(ext)) return true;
        if (sniffBytes <= 0) return false;
        var buf = ArrayPool<byte>.Shared.Rent(sniffBytes);
        try
        {
            using var fs = File.OpenRead(path);
            int read = await fs.ReadAsync(buf.AsMemory(0, sniffBytes), ct).ConfigureAwait(false);
            for (int i = 0; i < read; i++) if (buf[i] == 0) return true;
        }
        catch { return true; }
        finally { ArrayPool<byte>.Shared.Return(buf); }
        return false;
    }

    internal static IEnumerable<DiffHelper.FilePatch> ParseDiffLines(string repoRoot, string diff)
    {
        var lines = diff.Replace("\r\n", "\n").Split('\n');
        string? file = null;
        var hunks = new List<DiffHelper.Hunk>();
        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            if (line.StartsWith("+++ "))
            {
                if (file != null) { yield return new DiffHelper.FilePatch(file, hunks.ToArray()); hunks.Clear(); }
                var path = line[4..].Trim();
                if (path.StartsWith("b/")) path = path[2..];
                file = Path.Combine(repoRoot, path);
            }
            else if (line.StartsWith("@@ "))
            {
                var (h, idx) = ParseHunk(lines, i);
                hunks.Add(h);
                i = idx;
            }
        }
        if (file != null) yield return new DiffHelper.FilePatch(file, hunks.ToArray());
    }

    private static (DiffHelper.Hunk h, int idx) ParseHunk(string[] lines, int start)
    {
        var m = Regex.Match(lines[start], @"@@ -\d+(,\d+)? \+(?<nl>\d+)(,\d+)? @@");
        int newStart = int.Parse(m.Groups["nl"].Value);
        var hLines = new List<string>();
        int i = start + 1;
        for (; i < lines.Length; i++)
        {
            var l = lines[i];
            if (l.StartsWith("@@ ") || l.StartsWith("+++ ") || l.StartsWith("diff ") || l.StartsWith("--- ")) break;
            hLines.Add(l);
        }
        return (new DiffHelper.Hunk(newStart, hLines.ToArray()), i - 1);
    }
}

internal static class DiffHelper
{
    internal static string? ApplyHunks(string original, IReadOnlyList<Hunk> hunks)
    {
        var lines = original.Replace("\r\n", "\n").Split('\n');
        var result = new List<string>();
        int currentLine = 1;
        foreach (var h in hunks) ApplyHunk(h, lines, ref currentLine, result);
        while (currentLine <= lines.Length)
        {
            result.Add(lines[currentLine - 1]);
            currentLine++;
        }
        return string.Join('\n', result);
    }

    private static void ApplyHunk(Hunk h, string[] lines, ref int currentLine, List<string> result)
    {
        while (currentLine < h.NewStart && currentLine <= lines.Length)
        {
            result.Add(lines[currentLine - 1]);
            currentLine++;
        }
        foreach (var hl in h.Lines) ApplyLine(hl, lines, ref currentLine, result);
    }

    private static void ApplyLine(string hl, string[] lines, ref int currentLine, List<string> result)
    {
        if (hl.Length == 0) return;
        char tag = hl[0];
        var content = hl.Length > 1 ? hl.Substring(1) : string.Empty;
        switch (tag)
        {
            case ' ':
                if (currentLine <= lines.Length) result.Add(lines[currentLine - 1]); else result.Add(content);
                currentLine++;
                break;
            case '+':
                result.Add(content);
                break;
            case '-':
                if (currentLine <= lines.Length) currentLine++;
                break;
        }
    }

    internal readonly record struct FilePatch(string File, IReadOnlyList<Hunk> Hunks);
    internal readonly record struct Hunk(int NewStart, IReadOnlyList<string> Lines);
}
