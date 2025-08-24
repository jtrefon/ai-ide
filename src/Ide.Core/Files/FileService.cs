using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Ide.Core.Files;

public sealed class FileService : IFileService
{
    private static readonly HashSet<string> BinaryExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png",".jpg",".jpeg",".gif",".bmp",".webp",".svg",".tiff",".ico",".heic",".heif",
        ".dll",".exe",".so",".dylib",".a",".lib",".pdf",".zip",".gz",".tar",".7z",".rar",
        ".mp3",".mp4",".mov",".avi",".mkv",".class",".jar",".wasm"
    };

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
            try
            {
                if (!File.Exists(path))
                {
                    results.Add(new ReadResult(path, false, null, "Not found"));
                    continue;
                }
                var ext = Path.GetExtension(path);
                if (!string.IsNullOrEmpty(ext) && BinaryExtensions.Contains(ext))
                {
                    results.Add(new ReadResult(path, false, null, "Binary extension"));
                    continue;
                }
                var info = new FileInfo(path);
                if (info.Length > cap)
                {
                    results.Add(new ReadResult(path, false, null, $"File exceeds cap {cap} bytes"));
                    continue;
                }
                // sniff first 8KB for NUL
                var bufSize = (int)Math.Min(8192, info.Length);
                if (bufSize > 0)
                {
                    var tmp = ArrayPool<byte>.Shared.Rent(bufSize);
                    try
                    {
                        using var fs = File.OpenRead(path);
                        int read = await fs.ReadAsync(tmp.AsMemory(0, bufSize), ct).ConfigureAwait(false);
                        for (int i = 0; i < read; i++)
                        {
                            if (tmp[i] == 0)
                            {
                                results.Add(new ReadResult(path, false, null, "Binary (NUL detected)"));
                                goto Next;
                            }
                        }
                    }
                    finally
                    {
                        ArrayPool<byte>.Shared.Return(tmp);
                    }
                }
                var text = await File.ReadAllTextAsync(path, Encoding.UTF8, ct).ConfigureAwait(false);
                results.Add(new ReadResult(path, true, text, null));
            }
            catch (Exception ex)
            {
                results.Add(new ReadResult(path, false, null, ex.Message));
            }
        Next:;
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
            try
            {
                if (w.Content.IndexOf('\0') >= 0)
                {
                    results.Add(new WriteResult(w.Path, false, "Binary content (NUL) not allowed"));
                    continue;
                }
                var dir = Path.GetDirectoryName(w.Path);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

                if (atomic)
                {
                    var tmpPath = w.Path + ".tmp-" + Guid.NewGuid().ToString("N");
                    await File.WriteAllTextAsync(tmpPath, w.Content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), ct).ConfigureAwait(false);
                    // Use replace to be atomic on most platforms
                    if (File.Exists(w.Path))
                    {
                        File.Replace(tmpPath, w.Path, null, ignoreMetadataErrors: true);
                    }
                    else
                    {
                        File.Move(tmpPath, w.Path);
                    }
                }
                else
                {
                    await File.WriteAllTextAsync(w.Path, w.Content, new UTF8Encoding(false), ct).ConfigureAwait(false);
                }

                results.Add(new WriteResult(w.Path, true, null));
            }
            catch (Exception ex)
            {
                results.Add(new WriteResult(w.Path, false, ex.Message));
            }
        }
        return results;
    }

    public async Task<PatchResult> ApplyUnifiedDiffAsync(string repoRoot, string diff, bool atomic = true, CancellationToken ct = default)
    {
        try
        {
            // Normalize newlines
            var lines = diff.Replace("\r\n", "\n").Split('\n');
            var filePatches = new List<FilePatch>();

            string? currentFile = null;
            var hunks = new List<Hunk>();
            for (int i = 0; i < lines.Length; i++)
            {
                var line = lines[i];
                if (line.StartsWith("+++ "))
                {
                    // +++ b/path
                    var path = line.Substring(4).Trim();
                    if (path.StartsWith("b/")) path = path.Substring(2);
                    if (currentFile != null)
                    {
                        filePatches.Add(new FilePatch(currentFile, hunks.ToArray()));
                        hunks.Clear();
                    }
                    currentFile = Path.Combine(repoRoot, path);
                }
                else if (line.StartsWith("@@ "))
                {
                    // @@ -l,s +l2,s2 @@ optional_text
                    var m = Regex.Match(line, @"@@ -(?<ol>\d+)(,(?<oc>\d+))? \+(?<nl>\d+)(,(?<nc>\d+))? @@");
                    if (!m.Success) throw new InvalidOperationException($"Invalid hunk header: {line}");
                    int newStart = int.Parse(m.Groups["nl"].Value);
                    var hunkLines = new List<string>();
                    // collect until next hunk/file or end
                    int j = i + 1;
                    for (; j < lines.Length; j++)
                    {
                        var l2 = lines[j];
                        if (l2.StartsWith("@@ ") || l2.StartsWith("+++ ") || l2.StartsWith("diff ") || l2.StartsWith("--- ")) break;
                        hunkLines.Add(l2);
                    }
                    hunks.Add(new Hunk(newStart, hunkLines.ToArray()));
                    i = j - 1;
                }
            }
            if (currentFile != null)
            {
                filePatches.Add(new FilePatch(currentFile, hunks.ToArray()));
            }

            int changed = 0;
            foreach (var fp in filePatches)
            {
                if (ct.IsCancellationRequested) break;
                var original = File.Exists(fp.File) ? await File.ReadAllTextAsync(fp.File, Encoding.UTF8, ct).ConfigureAwait(false) : string.Empty;
                var newContent = ApplyHunks(original, fp.Hunks);
                if (newContent == null)
                {
                    return new PatchResult(false, changed, $"Failed to apply hunks for {fp.File}");
                }

                if (atomic)
                {
                    var dir = Path.GetDirectoryName(fp.File);
                    if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                    var tmp = fp.File + ".tmp-" + Guid.NewGuid().ToString("N");
                    await File.WriteAllTextAsync(tmp, newContent, new UTF8Encoding(false), ct).ConfigureAwait(false);
                    if (File.Exists(fp.File)) File.Replace(tmp, fp.File, null, true); else File.Move(tmp, fp.File);
                }
                else
                {
                    await File.WriteAllTextAsync(fp.File, newContent, new UTF8Encoding(false), ct).ConfigureAwait(false);
                }
                changed++;
            }

            return new PatchResult(true, changed, null);
        }
        catch (Exception ex)
        {
            return new PatchResult(false, 0, ex.Message);
        }
    }

    private static string? ApplyHunks(string original, IReadOnlyList<Hunk> hunks)
    {
        // Use \n internally
        var orig = original.Replace("\r\n", "\n");
        var lines = orig.Split('\n');
        var result = new List<string>();
        int currentLine = 1; // 1-based

        foreach (var h in hunks)
        {
            // copy unchanged until new start - 1
            while (currentLine < h.NewStart && currentLine <= lines.Length)
            {
                result.Add(lines[currentLine - 1]);
                currentLine++;
            }
            // apply hunk lines
            foreach (var hl in h.Lines)
            {
                // Ignore untagged empty lines (can occur from trailing newline in diff text)
                if (hl.Length == 0) { continue; }
                char tag = hl[0];
                var content = hl.Length > 1 ? hl.Substring(1) : string.Empty;
                switch (tag)
                {
                    case ' ': // context: ensure original matches at this position if available
                        if (currentLine <= lines.Length)
                        {
                            // best-effort; ignore mismatch
                            result.Add(lines[currentLine - 1]);
                            currentLine++;
                        }
                        else
                        {
                            result.Add(content);
                        }
                        break;
                    case '+':
                        result.Add(content);
                        break;
                    case '-':
                        if (currentLine <= lines.Length) currentLine++; // skip a line in original
                        break;
                    case '\\': // "\\ No newline at end of file" marker; ignore
                        break;
                    default:
                        // treat as context
                        result.Add(hl);
                        currentLine++;
                        break;
                }
            }
        }
        // append any remaining original lines
        while (currentLine <= lines.Length)
        {
            result.Add(lines[currentLine - 1]);
            currentLine++;
        }
        return string.Join('\n', result);
    }

    private readonly record struct FilePatch(string File, IReadOnlyList<Hunk> Hunks);
    private readonly record struct Hunk(int NewStart, IReadOnlyList<string> Lines);
}
