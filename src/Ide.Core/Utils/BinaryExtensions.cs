using System.Collections.Generic;

namespace Ide.Core.Utils;

/// <summary>
/// Provides a central list of binary file extensions.
/// </summary>
public static class BinaryExtensions
{
    /// <summary>
    /// Shared set of binary file extensions.
    /// </summary>
    public static HashSet<string> Set { get; } = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".svg", ".tiff", ".ico", ".heic", ".heif",
        ".dll", ".exe", ".so", ".dylib", ".a", ".lib", ".pdf", ".zip", ".gz", ".tar", ".7z", ".rar",
        ".mp3", ".mp4", ".mov", ".avi", ".mkv", ".class", ".jar", ".wasm",
        ".nupkg", ".snupkg", ".apk", ".aab", ".ipa"
    };
}

