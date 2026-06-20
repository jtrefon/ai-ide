import Foundation

/// Shared file exclusion utility for filesystem tools.
/// Uses the same exclude patterns as the codebase index
/// so vendor/dependency directories are hidden from tool output.
struct ToolFileExclusion {
    let projectRoot: URL

    /// Whether a URL should be excluded from tool output.
    func shouldExclude(_ url: URL) -> Bool {
        ToolFileExclusion.isExcluded(url: url)
    }

    /// Whether a directory should have its descendants skipped during
    /// recursive enumeration. Returns false for non-directories.
    func shouldSkipDescendants(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return false
        }
        return shouldExclude(url)
    }

    /// Returns the project-relative path for an absolute URL.
    func relativePath(for url: URL) -> String {
        let rootPath = projectRoot.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        if fullPath == rootPath { return "" }
        if fullPath.hasPrefix(rootPath + "/") {
            return String(fullPath.dropFirst(rootPath.count + 1))
        }
        return fullPath
    }

    /// Returns the relative path of a URL from the project root, or nil if outside.
    func tryRelativePath(for url: URL) -> String? {
        let rootPath = projectRoot.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        if fullPath == rootPath { return "" }
        if fullPath.hasPrefix(rootPath + "/") {
            return String(fullPath.dropFirst(rootPath.count + 1))
        }
        return nil
    }
}

// MARK: - Static matching (no project root needed)

extension ToolFileExclusion {
    static func isExcluded(url: URL) -> Bool {
        isExcluded(path: url.standardizedFileURL.path)
    }

    static func isExcluded(path: String) -> Bool {
        let patterns = IndexConfiguration.default.excludePatterns
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)

        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.contains("*") {
                let needle = trimmed.replacingOccurrences(of: "*", with: "")
                if !needle.isEmpty, normalized.contains(needle) { return true }
                continue
            }

            if trimmed.contains("/") {
                let needle = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !needle.isEmpty, normalized.contains(needle) { return true }
                continue
            }

            if components.contains(trimmed) { return true }
        }
        return false
    }
}
