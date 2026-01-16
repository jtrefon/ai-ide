import AppKit
import Foundation
import UniformTypeIdentifiers

class MockFileDialogService: FileDialogServiceProtocol {
    func openFileOrFolder() async -> URL? { nil }
    func openFolder() async -> URL? { nil }
    func saveFile(defaultFileName: String, allowedContentTypes: [UTType]) async -> URL? { nil }

    func promptForNewProjectFolder(defaultName: String) async -> URL? {
        URL(fileURLWithPath: "/Users/test/Desktop").appendingPathComponent(defaultName)
    }
}
