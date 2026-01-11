import Foundation

struct WorkspaceFallbackSearcher {
    private let fileManager: FileManager
    private let allowedExtensions: Set<String>

    init(
        fileManager: FileManager = .default,
        allowedExtensions: Set<String> = Set(AppConstants.Indexing.allowedExtensions)
    ) {
        self.fileManager = fileManager
        self.allowedExtensions = allowedExtensions
    }

    func search(pattern: String, projectRoot: URL, limit: Int) async -> [WorkspaceSearchMatch] {
        let needle = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        let root = projectRoot.standardizedFileURL
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var output: [WorkspaceSearchMatch] = []
        output.reserveCapacity(min(limit, 64))

        while let url = enumerator?.nextObject() as? URL {
            if Task.isCancelled { break }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if shouldSkipDirectory(url) {
                    enumerator?.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            guard shouldSearchFile(url) else { continue }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            appendMatches(
                from: content,
                in: url,
                root: root,
                pattern: needle,
                limit: limit,
                output: &output
            )

            if output.count >= limit { break }
        }

        return output
    }

    private func shouldSkipDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == ".git" || name == ".ide" || name == "node_modules"
    }

    private func shouldSearchFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return true }
        return allowedExtensions.contains(ext)
    }

    private func appendMatches(
        from content: String,
        in url: URL,
        root: URL,
        pattern: String,
        limit: Int,
        output: inout [WorkspaceSearchMatch]
    ) {
        let lines = content.components(separatedBy: .newlines)
        let relative = makeRelativePath(url: url, root: root)

        for (idx, line) in lines.enumerated() {
            if Task.isCancelled { break }
            if !line.contains(pattern) { continue }

            output.append(
                WorkspaceSearchMatch(
                    relativePath: relative,
                    line: idx + 1,
                    snippet: makeSnippet(from: line)
                )
            )

            if output.count >= limit { return }
        }
    }

    private func makeRelativePath(url: URL, root: URL) -> String {
        if url.path.hasPrefix(root.path + "/") {
            return String(url.path.dropFirst(root.path.count + 1))
        }
        return url.lastPathComponent
    }

    private func makeSnippet(from line: String) -> String {
        let snippetMax = 240
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > snippetMax {
            return String(trimmed.prefix(snippetMax)) + "…"
        }
        return trimmed
    }
}
