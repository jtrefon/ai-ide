import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class FilePickerService: ObservableObject {
    @Published var lastError: String? = nil

    func openFile(onSuccess: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.swiftSource, .plainText, .sourceCode]

        if panel.runModal() == .OK {
            if let url = panel.url {
                lastError = nil
                onSuccess(url)
            }
        }
    }

    func openFolder(onSuccess: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"

        if panel.runModal() == .OK {
            if let url = panel.url {
                lastError = nil
                onSuccess(url)
            }
        }
    }

    func saveFileAs(suggestedFileName: String, allowedContentTypes: [UTType], onSuccess: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.nameFieldStringValue = suggestedFileName

        if panel.runModal() == .OK {
            if let url = panel.url {
                lastError = nil
                onSuccess(url)
            }
        }
    }
}
