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
            return defaultValue
        }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return defaultValue
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
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
