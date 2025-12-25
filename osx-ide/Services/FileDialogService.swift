import AppKit
import UniformTypeIdentifiers

/// Handles user-facing file dialogs.
@MainActor
final class FileDialogService: FileDialogServiceProtocol {
    private let windowProvider: WindowProviding

    init(windowProvider: WindowProviding) {
        self.windowProvider = windowProvider
    }

    func openFileOrFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.swiftSource, .plainText, .sourceCode, .folder]

        return await runOpenPanel(panel)
    }

    func openFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"

        return await runOpenPanel(panel)
    }

    func saveFile(defaultFileName: String, allowedContentTypes: [UTType]) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.nameFieldStringValue = defaultFileName

        return await runSavePanel(panel)
    }

    func selectDirectory() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.title = "Choose Location for New Project"

        return await runOpenPanel(panel)
    }

    private func runOpenPanel(_ panel: NSOpenPanel) async -> URL? {
        await withCheckedContinuation { continuation in
            if let window = windowProvider.window ?? NSApp.keyWindow {
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            } else {
                let response = panel.runModal()
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private func runSavePanel(_ panel: NSSavePanel) async -> URL? {
        await withCheckedContinuation { continuation in
            if let window = windowProvider.window ?? NSApp.keyWindow {
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            } else {
                let response = panel.runModal()
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
