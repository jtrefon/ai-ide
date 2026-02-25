import Foundation

protocol PromptRepositoryProtocol {
    func prompt(
        key: String,
        defaultValue: String,
        projectRoot: URL?
    ) -> String
}

final class PromptRepository: PromptRepositoryProtocol, @unchecked Sendable {
    static let shared = PromptRepository()

    /// Controls whether fallback to inline default values is allowed when prompt files cannot be found.
    /// When `false` (default), the app will crash if a prompt file cannot be loaded.
    /// This ensures prompt optimization efforts are not undermined by silent fallbacks.
    /// - Note: This is intentionally mutable global state for runtime configuration.
    ///         Access is expected to be infrequent (typically at app startup).
    nonisolated(unsafe) static var allowFallback: Bool = false

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prompt(
        key: String,
        defaultValue: String,
        projectRoot: URL?
    ) -> String {
        guard let url = resolvePromptURL(key: key, projectRoot: projectRoot) else {
            if Self.allowFallback {
                return defaultValue
            }
            fatalError("PromptRepository: Prompt file not found for key '\(key)'. Set allowFallback=true to use inline fallbacks.")
        }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            if Self.allowFallback {
                return defaultValue
            }
            fatalError("PromptRepository: Failed to read prompt file for key '\(key)' at path '\(url.path)'. Set allowFallback=true to use inline fallbacks.")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if Self.allowFallback {
                return defaultValue
            }
            fatalError("PromptRepository: Prompt file is empty for key '\(key)' at path '\(url.path)'. Set allowFallback=true to use inline fallbacks.")
        }
        return trimmed
    }

    private func resolvePromptURL(key: String, projectRoot: URL?) -> URL? {
        let relativePath = "Prompts/\(key).md"

        if let projectRoot {
            let direct = projectRoot.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: direct.path) {
                return direct
            }
        }

        if let envRoot = ProcessInfo.processInfo.environment["OSX_IDE_PROMPTS_ROOT"],
           !envRoot.isEmpty {
            let envURL = URL(fileURLWithPath: envRoot, isDirectory: true)
            let candidate = envURL.appendingPathComponent("\(key).md")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        return searchUpwardsForPromptsFolder(from: cwd, key: key)
    }

    private func searchUpwardsForPromptsFolder(from start: URL, key: String) -> URL? {
        var current = start
        for _ in 0..<8 {
            let promptsFolder = current.appendingPathComponent("Prompts", isDirectory: true)
            if fileManager.fileExists(atPath: promptsFolder.path) {
                let candidate = promptsFolder.appendingPathComponent("\(key).md")
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return nil
    }
}
