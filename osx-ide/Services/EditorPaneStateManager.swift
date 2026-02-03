import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Manages file editor state and operations
@MainActor
final class EditorPaneStateManager: ObservableObject {
    @Published var tabs: [EditorTab] = []
    @Published var activeTabID: UUID?
    @Published var selectedFile: String?
    @Published var editorContent: String = ""
    @Published var editorLanguage: String = "swift"
    @Published var isDirty: Bool = false
    @Published var selectedRange: NSRange?
    @Published var isLoadingFile: Bool = false

    let fileEditorService: FileEditorServiceProtocol
    let fileDialogService: FileDialogServiceProtocol
    let fileSystemService: FileSystemService

    let languageDetector: EditorLanguageDetecting
    let editingStateManager: EditingStateManager
    let tabManager: EditorTabManager
    let fileWatchCoordinator: FileWatchCoordinator

    init(
        fileEditorService: FileEditorServiceProtocol,
        fileDialogService: FileDialogServiceProtocol,
        fileSystemService: FileSystemService
    ) {
        self.fileEditorService = fileEditorService
        self.fileDialogService = fileDialogService
        self.fileSystemService = fileSystemService

        let languageDetector = DefaultEditorLanguageDetector()
        self.languageDetector = languageDetector
        self.editingStateManager = EditingStateManager(languageDetector: languageDetector)
        self.tabManager = EditorTabManager()
        self.fileWatchCoordinator = FileWatchCoordinator()
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stopWatchingAllFiles()
        }
    }
}
