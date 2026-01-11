import Foundation

protocol EditorLanguageDetecting {
    func detectLanguageForUntitledContent(currentLanguage: String, content: String) -> String?
    func languageForFileExtension(_ fileExtension: String) -> String
}

struct DefaultEditorLanguageDetector: EditorLanguageDetecting {
    func detectLanguageForUntitledContent(currentLanguage: String, content: String) -> String? {
        guard currentLanguage == "swift" || currentLanguage == "text" else { return nil }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.first == "{" || trimmed.first == "[" else { return nil }
        guard isValidJSON(trimmed) else { return nil }

        return "json"
    }

    func languageForFileExtension(_ fileExtension: String) -> String {
        let normalized = fileExtension.lowercased()
        return languageByFileExtension[normalized] ?? "text"
    }

    private func isValidJSON(_ content: String) -> Bool {
        guard let data = content.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }

    private let languageByFileExtension: [String: String] = [
        "swift": "swift",
        "js": "javascript",
        "jsx": "jsx",
        "ts": "typescript",
        "tsx": "tsx",
        "py": "python",
        "html": "html",
        "css": "css",
        "json": "json"
    ]
}
