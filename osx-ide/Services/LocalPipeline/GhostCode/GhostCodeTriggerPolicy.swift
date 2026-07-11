import Foundation

@MainActor
struct GhostCodeTriggerPolicy {
    private let supportedLanguages: Set<String> = [
        "swift", "objective-c", "c", "cpp", "c#", "csharp",
        "typescript", "tsx", "javascript", "jsx",
        "python", "rust", "go", "golang",
        "java", "kotlin", "ruby", "scala",
        "php", "dart", "lua", "haskell", "julia", "zig",
        "html", "css", "shell", "bash", "sql"
    ]

    func shouldAutoTrigger(for snapshot: InlineCompletionEditorSnapshot, idleMs: Double) -> Bool {
        guard !snapshot.buffer.isEmpty else { return false }
        guard !snapshot.isComposingText else { return false }
        guard snapshot.selectionLength == 0 else { return false }
        guard idleMs >= 400 else { return false }
        let normalizedLanguage = snapshot.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard supportedLanguages.contains(normalizedLanguage) else { return false }
        guard cursorAtEndOfLine(in: snapshot) else { return false }
        return true
    }

    func shouldManualTrigger(for snapshot: InlineCompletionEditorSnapshot) -> Bool {
        !snapshot.buffer.isEmpty && !snapshot.isComposingText
    }

    private func cursorAtEndOfLine(in snapshot: InlineCompletionEditorSnapshot) -> Bool {
        let nsBuffer = snapshot.buffer as NSString
        let cursor = max(0, min(snapshot.cursorPosition, nsBuffer.length))
        if cursor >= nsBuffer.length { return true }
        let lineRange = nsBuffer.lineRange(for: NSRange(location: cursor, length: 0))
        let afterCursor = nsBuffer.substring(with: NSRange(location: cursor, length: lineRange.location + lineRange.length - cursor))
        return afterCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
