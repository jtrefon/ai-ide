import Foundation

public struct WorkspaceSearchMatch: Identifiable, Equatable, Sendable {
    public let id: String
    public let relativePath: String
    public let line: Int
    public let snippet: String

    public init(relativePath: String, line: Int, snippet: String) {
        self.relativePath = relativePath
        self.line = line
        self.snippet = snippet
        self.id = "\(relativePath):\(line):\(snippet)"
    }
}

@MainActor
public final class WorkspaceSearchService {
    private let codebaseIndexProvider: () -> CodebaseIndexProtocol?
    private let settingsStore: SettingsStore

    public init(codebaseIndexProvider: @escaping () -> CodebaseIndexProtocol?) {
        self.codebaseIndexProvider = codebaseIndexProvider
        self.settingsStore = SettingsStore(userDefaults: .standard)
    }

    public func search(pattern: String, projectRoot: URL, limit: Int = 200) async -> [WorkspaceSearchMatch] {
        let needle = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return [] }

        if let index = codebaseIndexProvider(), settingsStore.bool(forKey: AppConstants.Storage.codebaseIndexEnabledKey, default: true) {
            if let matches = try? await index.searchIndexedText(pattern: needle, limit: limit) {
                return matches.compactMap(Self.parseIndexedMatchLine)
            }
        }

        return await fallbackSearch(pattern: needle, projectRoot: projectRoot, limit: limit)
    }

    private func fallbackSearch(pattern: String, projectRoot: URL, limit: Int) async -> [WorkspaceSearchMatch] {
        let fm = FileManager.default
        let root = projectRoot.standardizedFileURL

        let allowed = Set(AppConstants.Indexing.allowedExtensions)
        let enumerator = fm.enumerator(
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
                let name = url.lastPathComponent.lowercased()
                if name == ".git" || name == ".ide" || name == "node_modules" {
                    enumerator?.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty, !allowed.contains(ext) {
                continue
            }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                if Task.isCancelled { break }
                if !line.contains(pattern) { continue }

                let rel: String
                if url.path.hasPrefix(root.path + "/") {
                    rel = String(url.path.dropFirst(root.path.count + 1))
                } else {
                    rel = url.lastPathComponent
                }

                let snippetMax = 240
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = trimmed.count > snippetMax ? String(trimmed.prefix(snippetMax)) + "…" : trimmed

                output.append(WorkspaceSearchMatch(relativePath: rel, line: idx + 1, snippet: snippet))
                if output.count >= limit { return output }
            }
        }

        return output
    }

    static func parseIndexedMatchLine(_ s: String) -> WorkspaceSearchMatch? {
        // Expected: rel/path:line: snippet
        // We split the first two ":" occurrences.
        let parts = s.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        let path = String(parts[0])
        let lineStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let line = Int(lineStr) ?? 1
        let snippet = parts.count >= 3 ? String(parts[2]).trimmingCharacters(in: .whitespaces) : ""

        return WorkspaceSearchMatch(relativePath: path, line: line, snippet: snippet)
    }
}
