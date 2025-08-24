using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Ide.Core.Files;

public sealed record ReadResult(string Path, bool Ok, string? Content, string? Error);
public sealed record FileWrite(string Path, string Content);
public sealed record WriteResult(string Path, bool Ok, string? Error);
public sealed record PatchResult(bool Ok, int FilesChanged, string? Error);

public interface IFileService
{
    /// <summary>
    /// Reads multiple text files safely (UTF-8). Skips binaries and files exceeding maxBytes.
    /// </summary>
    Task<IReadOnlyList<ReadResult>> ReadFilesAsync(
        IEnumerable<string> files,
        int? maxBytes = null,
        CancellationToken ct = default);

    /// <summary>
    /// Writes multiple text files atomically (tmp + replace). Creates parent directories.
    /// Rejects content containing NUL bytes.
    /// </summary>
    Task<IReadOnlyList<WriteResult>> WriteFilesAsync(
        IEnumerable<FileWrite> writes,
        bool atomic = true,
        CancellationToken ct = default);

    /// <summary>
    /// Applies a unified diff string (git-style) under repoRoot. Best-effort minimal parser.
    /// </summary>
    Task<PatchResult> ApplyUnifiedDiffAsync(
        string repoRoot,
        string diff,
        bool atomic = true,
        CancellationToken ct = default);
}
