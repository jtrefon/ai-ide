import AppKit
import UniformTypeIdentifiers

/// Handles user-facing file dialogs.
@MainActor
final class FileDialogService {
    func openFileOrFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.swiftSource, .plainText, .sourceCode, .folder]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func openFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func saveFile(defaultFileName: String, allowedContentTypes: [UTType]) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.nameFieldStringValue = defaultFileName
        return panel.runModal() == .OK ? panel.url : nil
    }
}
