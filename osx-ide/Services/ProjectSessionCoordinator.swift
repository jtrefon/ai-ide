import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
final class ProjectSessionCoordinator {
    private let projectSessionStore = ProjectSessionStore()

    private weak var window: NSWindow?
    private var saveSessionTask: Task<Void, Never>?
    private var isRestoringSession: Bool = false

    private let workspace: WorkspaceStateManager
    private let ui: UIStateManager
    private let fileEditor: FileEditorStateManager
    private let conversationManager: ConversationManagerProtocol

    private let getFileTreeExpandedRelativePaths: () -> Set<String>
    private let setFileTreeExpandedRelativePaths: (Set<String>) -> Void

    private let getShowHiddenFilesInFileTree: () -> Bool
    private let setShowHiddenFilesInFileTree: (Bool) -> Void

    private let getLanguageOverridesByRelativePath: () -> [String: String]
    private let setLanguageOverridesByRelativePath: ([String: String]) -> Void

    private let relativePathForURL: (URL) -> String?
    private let loadFileFromURL: (URL) -> Void

    private var cancellables = Set<AnyCancellable>()

    init(
        workspace: WorkspaceStateManager,
        ui: UIStateManager,
        fileEditor: FileEditorStateManager,
        conversationManager: ConversationManagerProtocol,
        getFileTreeExpandedRelativePaths: @escaping () -> Set<String>,
        setFileTreeExpandedRelativePaths: @escaping (Set<String>) -> Void,
        getShowHiddenFilesInFileTree: @escaping () -> Bool,
        setShowHiddenFilesInFileTree: @escaping (Bool) -> Void,
        getLanguageOverridesByRelativePath: @escaping () -> [String: String],
        setLanguageOverridesByRelativePath: @escaping ([String: String]) -> Void,
        relativePathForURL: @escaping (URL) -> String?,
        loadFileFromURL: @escaping (URL) -> Void
    ) {
        self.workspace = workspace
        self.ui = ui
        self.fileEditor = fileEditor
        self.conversationManager = conversationManager
        self.getFileTreeExpandedRelativePaths = getFileTreeExpandedRelativePaths
        self.setFileTreeExpandedRelativePaths = setFileTreeExpandedRelativePaths
        self.getShowHiddenFilesInFileTree = getShowHiddenFilesInFileTree
        self.setShowHiddenFilesInFileTree = setShowHiddenFilesInFileTree

        self.getLanguageOverridesByRelativePath = getLanguageOverridesByRelativePath
        self.setLanguageOverridesByRelativePath = setLanguageOverridesByRelativePath
        self.relativePathForURL = relativePathForURL
        self.loadFileFromURL = loadFileFromURL
    }

    func attachWindow(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSaveProjectSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSaveProjectSession()
            }
            .store(in: &cancellables)
    }

    func loadProjectSessionIfAvailable() {
        guard let root = workspace.currentDirectory else { return }
        Task { [weak self] in
            await self?.loadProjectSession(for: root)
        }
    }

    func loadProjectSession(for projectRoot: URL) async {
        await loadProjectSessionImpl(for: projectRoot)
    }

    func scheduleSaveProjectSession() {
        guard !isRestoringSession else { return }
        saveSessionTask?.cancel()
        saveSessionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { [weak self] in
                self?.saveProjectSessionNow()
            }
        }
    }

    private func loadExistingNonDirectoryFileIfPresent(_ url: URL) {
        let isDir = (try? url.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
        if FileManager.default.fileExists(atPath: url.path), !isDir {
            loadFileFromURL(url)
        }
    }

    private func restoreTabs(
        pane: FileEditorStateManager.PaneID,
        projectRoot: URL,
        openTabRelativePaths: [String],
        activeTabRelativePath: String?
    ) {
        guard !openTabRelativePaths.isEmpty else { return }
        fileEditor.focus(pane)
        for rel in openTabRelativePaths {
            loadExistingNonDirectoryFileIfPresent(projectRoot.appendingPathComponent(rel))
        }
        if let activeRel = activeTabRelativePath {
            fileEditor.activateTab(filePath: projectRoot.appendingPathComponent(activeRel).path)
        }
    }

    private func relativePathForActiveTab(
        activeTabID: UUID?,
        tabs: [EditorPaneStateManager.EditorTab]
    ) -> String? {
        guard let activeTabID,
              let activeTab = tabs.first(where: { $0.id == activeTabID }) else {
            return nil
        }
        return relativePathForURL(URL(fileURLWithPath: activeTab.filePath))
    }

    private func loadProjectSessionImpl(for projectRoot: URL) async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        await projectSessionStore.setProjectRoot(projectRoot)

        guard let session = try? await projectSessionStore.load() else {
            scheduleSaveProjectSession()
            return
        }

        if let frame = session.windowFrame?.rect, let window {
            window.setFrame(frame, display: true)
        }

        ui.isSidebarVisible = session.isSidebarVisible
        ui.isTerminalVisible = session.isTerminalVisible
        ui.isAIChatVisible = session.isAIChatVisible
        ui.sidebarWidth = session.sidebarWidth
        ui.terminalHeight = session.terminalHeight
        ui.chatPanelWidth = session.chatPanelWidth

        if let theme = AppTheme(rawValue: session.selectedThemeRawValue) {
            ui.selectedTheme = theme
        }
        ui.showLineNumbers = session.showLineNumbers
        ui.wordWrap = session.wordWrap
        ui.minimapVisible = session.minimapVisible

        setShowHiddenFilesInFileTree(session.showHiddenFilesInFileTree)

        setLanguageOverridesByRelativePath(session.languageOverridesByRelativePath)

        if let mode = AIMode(rawValue: session.aiModeRawValue) {
            conversationManager.currentMode = mode
        }

        setFileTreeExpandedRelativePaths(Set(session.fileTreeExpandedRelativePaths))

        fileEditor.newFile()

        let splitAxis = FileEditorStateManager.SplitAxis(rawValue: session.splitAxisRawValue) ?? .vertical
        fileEditor.splitAxis = splitAxis
        fileEditor.isSplitEditor = session.isSplitEditor
        let focused = FileEditorStateManager.PaneID(rawValue: session.focusedEditorPaneRawValue) ?? .primary
        fileEditor.focusedPane = focused

        let primaryRelPaths = !session.primaryOpenTabRelativePaths.isEmpty
            ? session.primaryOpenTabRelativePaths
            : session.openTabRelativePaths
        let primaryActiveRel = session.primaryActiveTabRelativePath ?? session.activeTabRelativePath

        restoreTabs(
            pane: .primary,
            projectRoot: projectRoot,
            openTabRelativePaths: primaryRelPaths,
            activeTabRelativePath: primaryActiveRel
        )

        if session.isSplitEditor {
            restoreTabs(
                pane: .secondary,
                projectRoot: projectRoot,
                openTabRelativePaths: session.secondaryOpenTabRelativePaths,
                activeTabRelativePath: session.secondaryActiveTabRelativePath
            )
        }

        fileEditor.focus(focused)

        if primaryRelPaths.isEmpty, let rel = session.lastOpenFileRelativePath {
            loadExistingNonDirectoryFileIfPresent(projectRoot.appendingPathComponent(rel))
        }
    }

    private func saveProjectSessionNow() {
        guard !isRestoringSession else { return }
        guard let projectRoot = workspace.currentDirectory else { return }

        let windowFrame = window.map { ProjectSession.WindowFrame(rect: $0.frame) }
        let lastOpenRelative: String?
        let openTabRelatives: [String]
        let activeRelative: String?

        let focusedPaneState = fileEditor.focusedPaneState

        activeRelative = relativePathForActiveTab(
            activeTabID: focusedPaneState.activeTabID,
            tabs: focusedPaneState.tabs
        )

        openTabRelatives = focusedPaneState.tabs.compactMap {
            relativePathForURL(URL(fileURLWithPath: $0.filePath))
        }
        lastOpenRelative = activeRelative

        let primaryTabs = fileEditor.primaryPane.tabs.compactMap {
            relativePathForURL(URL(fileURLWithPath: $0.filePath))
        }
        let secondaryTabs = fileEditor.secondaryPane.tabs.compactMap {
            relativePathForURL(URL(fileURLWithPath: $0.filePath))
        }

        let primaryActive = relativePathForActiveTab(
            activeTabID: fileEditor.primaryPane.activeTabID,
            tabs: fileEditor.primaryPane.tabs
        )

        let secondaryActive = relativePathForActiveTab(
            activeTabID: fileEditor.secondaryPane.activeTabID,
            tabs: fileEditor.secondaryPane.tabs
        )

        let session = ProjectSession(
            uiConfiguration: UIConfiguration(
                windowFrame: windowFrame,
                isSidebarVisible: ui.isSidebarVisible,
                isTerminalVisible: ui.isTerminalVisible,
                isAIChatVisible: ui.isAIChatVisible,
                sidebarWidth: ui.sidebarWidth,
                terminalHeight: ui.terminalHeight,
                chatPanelWidth: ui.chatPanelWidth
            ),
            editor: EditorConfiguration(
                selectedThemeRawValue: ui.selectedTheme.rawValue,
                showLineNumbers: ui.showLineNumbers,
                wordWrap: ui.wordWrap,
                minimapVisible: ui.minimapVisible,
                showHiddenFilesInFileTree: getShowHiddenFilesInFileTree()
            ),
            fileState: FileState(
                lastOpenFileRelativePath: lastOpenRelative,
                openTabRelativePaths: openTabRelatives,
                activeTabRelativePath: activeRelative
            ),
            splitEditor: SplitEditorState(
                isSplitEditor: fileEditor.isSplitEditor,
                splitAxisRawValue: fileEditor.splitAxis.rawValue,
                focusedEditorPaneRawValue: fileEditor.focusedPane.rawValue,
                primaryOpenTabRelativePaths: primaryTabs,
                primaryActiveTabRelativePath: primaryActive,
                secondaryOpenTabRelativePaths: secondaryTabs,
                secondaryActiveTabRelativePath: secondaryActive
            ),
            fileTree: FileTreeState(
                fileTreeExpandedRelativePaths: Array(getFileTreeExpandedRelativePaths()).sorted(),
                languageOverridesByRelativePath: getLanguageOverridesByRelativePath()
            ),
            aiModeRawValue: conversationManager.currentMode.rawValue
        )

        Task {
            await projectSessionStore.setProjectRoot(projectRoot)
            try? await projectSessionStore.save(session)
        }
    }
}
