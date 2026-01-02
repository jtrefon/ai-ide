//
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import Combine

/// Protocol for application error management
@MainActor
public protocol ErrorManagerProtocol: AnyObject {
    var currentError: AppError? { get }
    var showErrorAlert: Bool { get set }
    func handle(_ error: AppError)
    func handle(_ error: Error, context: String)
    func dismissError()
    var statePublisher: ObservableObjectPublisher { get }
}

public extension ErrorManagerProtocol where Self: ObservableObject {
    var statePublisher: ObservableObjectPublisher {
        return self.objectWillChange as! ObservableObjectPublisher
    }
}

/// Protocol defining UI-related persistence and settings
@MainActor
protocol UIServiceProtocol {
    func loadSettings() -> UISettings
    func saveSettings(_ settings: UISettings)
    func resetToDefaults()
    func setTheme(_ theme: AppTheme)
    func setFontSize(_ size: Double)
    func setFontFamily(_ family: String)
    func setShowLineNumbers(_ show: Bool)
    func setWordWrap(_ wrap: Bool)
    func setMinimapVisible(_ visible: Bool)
    func setSidebarWidth(_ width: Double)
    func setTerminalHeight(_ height: Double)
    func setChatPanelWidth(_ width: Double)
    func exportSettings() -> [String: Any]
    func importSettings(_ settings: [String: Any])
}

/// Protocol defining workspace and file system operations
@MainActor
protocol WorkspaceServiceProtocol: AnyObject {
    var currentDirectory: URL? { get set }
    func createFile(named name: String, in directory: URL)
    func createFolder(named name: String, in directory: URL)
    func navigateToParent()
    func navigateTo(subdirectory: String)
    func isValidPath(_ path: String) -> Bool
    func handleError(_ error: AppError)
    var statePublisher: ObservableObjectPublisher { get }
}

extension WorkspaceServiceProtocol where Self: ObservableObject {
    var statePublisher: ObservableObjectPublisher {
        return self.objectWillChange as! ObservableObjectPublisher
    }
}

/// Protocol for file editing operations
@MainActor
protocol FileEditorServiceProtocol: AnyObject {
    var selectedFile: String? { get set }
    var editorContent: String { get set }
    var editorLanguage: String { get set }
    var isDirty: Bool { get }
    var canSave: Bool { get }
    var displayName: String { get }
    
    func loadFile(from url: URL)
    func saveFile()
    func saveFileAs(to url: URL)
    func newFile()
    func handleError(_ error: AppError)
    var statePublisher: ObservableObjectPublisher { get }
}

extension FileEditorServiceProtocol where Self: ObservableObject {
    var statePublisher: ObservableObjectPublisher {
        return self.objectWillChange as! ObservableObjectPublisher
    }
}

/// Protocol for user-facing file dialogs
@MainActor
protocol FileDialogServiceProtocol {
    func openFileOrFolder() async -> URL?
    func openFolder() async -> URL?
    func saveFile(defaultFileName: String, allowedContentTypes: [UTType]) async -> URL?
}

/// Protocol for AI conversation management
@MainActor
public protocol ConversationManagerProtocol: AnyObject {
    var messages: [ChatMessage] { get }
    var currentInput: String { get set }
    var isSending: Bool { get }
    var error: String? { get }
    var currentMode: AIMode { get set }
    
    func sendMessage()
    func sendMessage(context: String?)
    func clearConversation()
    func updateProjectRoot(_ root: URL)
    var statePublisher: ObservableObjectPublisher { get }
}

public extension ConversationManagerProtocol where Self: ObservableObject {
    var statePublisher: ObservableObjectPublisher {
        return self.objectWillChange as! ObservableObjectPublisher
    }
}
