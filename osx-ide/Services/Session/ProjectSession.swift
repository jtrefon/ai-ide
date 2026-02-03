import Foundation

public struct ProjectSession: Codable, Sendable {
    public typealias WindowFrame = ProjectSessionWindowFrame

    public var uiConfiguration: UIConfiguration
    public var editor: EditorConfiguration
    public var fileState: FileState
    public var splitEditor: SplitEditorState
    public var fileTree: FileTreeState
    public var aiModeRawValue: String

    public init(
        uiConfiguration: UIConfiguration,
        editor: EditorConfiguration,
        fileState: FileState,
        splitEditor: SplitEditorState,
        fileTree: FileTreeState,
        aiModeRawValue: String = "Chat"
    ) {
        self.uiConfiguration = uiConfiguration
        self.editor = editor
        self.fileState = fileState
        self.splitEditor = splitEditor
        self.fileTree = fileTree
        self.aiModeRawValue = aiModeRawValue
    }

    @available(*, deprecated, message: "Use the new builder pattern with grouped configurations")
    public init(
        windowFrame: WindowFrame?,
        isSidebarVisible: Bool,
        isTerminalVisible: Bool,
        isAIChatVisible: Bool,
        sidebarWidth: Double,
        terminalHeight: Double,
        chatPanelWidth: Double,
        selectedThemeRawValue: String,
        showLineNumbers: Bool,
        wordWrap: Bool,
        minimapVisible: Bool,
        showHiddenFilesInFileTree: Bool,
        aiModeRawValue: String,
        lastOpenFileRelativePath: String?,
        openTabRelativePaths: [String],
        activeTabRelativePath: String?,
        isSplitEditor: Bool,
        splitAxisRawValue: String,
        focusedEditorPaneRawValue: String,
        primaryOpenTabRelativePaths: [String],
        primaryActiveTabRelativePath: String?,
        secondaryOpenTabRelativePaths: [String],
        secondaryActiveTabRelativePath: String?,
        fileTreeExpandedRelativePaths: [String],
        languageOverridesByRelativePath: [String: String]
    ) {
        self.uiConfiguration = UIConfiguration(
            windowFrame: windowFrame,
            isSidebarVisible: isSidebarVisible,
            isTerminalVisible: isTerminalVisible,
            isAIChatVisible: isAIChatVisible,
            sidebarWidth: sidebarWidth,
            terminalHeight: terminalHeight,
            chatPanelWidth: chatPanelWidth
        )

        self.editor = EditorConfiguration(
            selectedThemeRawValue: selectedThemeRawValue,
            showLineNumbers: showLineNumbers,
            wordWrap: wordWrap,
            minimapVisible: minimapVisible,
            showHiddenFilesInFileTree: showHiddenFilesInFileTree
        )

        self.fileState = FileState(
            lastOpenFileRelativePath: lastOpenFileRelativePath,
            openTabRelativePaths: openTabRelativePaths,
            activeTabRelativePath: activeTabRelativePath
        )

        self.splitEditor = SplitEditorState(
            isSplitEditor: isSplitEditor,
            splitAxisRawValue: splitAxisRawValue,
            focusedEditorPaneRawValue: focusedEditorPaneRawValue,
            primaryOpenTabRelativePaths: primaryOpenTabRelativePaths,
            primaryActiveTabRelativePath: primaryActiveTabRelativePath,
            secondaryOpenTabRelativePaths: secondaryOpenTabRelativePaths,
            secondaryActiveTabRelativePath: secondaryActiveTabRelativePath
        )

        self.fileTree = FileTreeState(
            fileTreeExpandedRelativePaths: fileTreeExpandedRelativePaths,
            languageOverridesByRelativePath: languageOverridesByRelativePath
        )

        self.aiModeRawValue = aiModeRawValue
    }

    public static func `default`() -> ProjectSession {
        ProjectSession(
            uiConfiguration: UIConfiguration(windowFrame: nil),
            editor: EditorConfiguration(),
            fileState: FileState(),
            splitEditor: SplitEditorState(),
            fileTree: FileTreeState()
        )
    }

    public static func with(windowFrame: WindowFrame?) -> ProjectSessionBuilder {
        ProjectSessionBuilder().uiConfiguration(UIConfiguration(windowFrame: windowFrame))
    }

    @available(*, deprecated, message: "Use ui.windowFrame instead")
    public var windowFrame: WindowFrame? { uiConfiguration.windowFrame }

    @available(*, deprecated, message: "Use ui.isSidebarVisible instead")
    public var isSidebarVisible: Bool { uiConfiguration.isSidebarVisible }

    @available(*, deprecated, message: "Use ui.isTerminalVisible instead")
    public var isTerminalVisible: Bool { uiConfiguration.isTerminalVisible }

    @available(*, deprecated, message: "Use ui.isAIChatVisible instead")
    public var isAIChatVisible: Bool { uiConfiguration.isAIChatVisible }

    @available(*, deprecated, message: "Use ui.sidebarWidth instead")
    public var sidebarWidth: Double { uiConfiguration.sidebarWidth }

    @available(*, deprecated, message: "Use ui.terminalHeight instead")
    public var terminalHeight: Double { uiConfiguration.terminalHeight }

    @available(*, deprecated, message: "Use ui.chatPanelWidth instead")
    public var chatPanelWidth: Double { uiConfiguration.chatPanelWidth }

    @available(*, deprecated, message: "Use editor.selectedThemeRawValue instead")
    public var selectedThemeRawValue: String { editor.selectedThemeRawValue }

    @available(*, deprecated, message: "Use editor.showLineNumbers instead")
    public var showLineNumbers: Bool { editor.showLineNumbers }

    @available(*, deprecated, message: "Use editor.wordWrap instead")
    public var wordWrap: Bool { editor.wordWrap }

    @available(*, deprecated, message: "Use editor.minimapVisible instead")
    public var minimapVisible: Bool { editor.minimapVisible }

    @available(*, deprecated, message: "Use editor.showHiddenFilesInFileTree instead")
    public var showHiddenFilesInFileTree: Bool { editor.showHiddenFilesInFileTree }

    @available(*, deprecated, message: "Use fileState.lastOpenFileRelativePath instead")
    public var lastOpenFileRelativePath: String? { fileState.lastOpenFileRelativePath }

    @available(*, deprecated, message: "Use fileState.openTabRelativePaths instead")
    public var openTabRelativePaths: [String] { fileState.openTabRelativePaths }

    @available(*, deprecated, message: "Use fileState.activeTabRelativePath instead")
    public var activeTabRelativePath: String? { fileState.activeTabRelativePath }

    @available(*, deprecated, message: "Use splitEditor.isSplitEditor instead")
    public var isSplitEditor: Bool { splitEditor.isSplitEditor }

    @available(*, deprecated, message: "Use splitEditor.splitAxisRawValue instead")
    public var splitAxisRawValue: String { splitEditor.splitAxisRawValue }

    @available(*, deprecated, message: "Use splitEditor.focusedEditorPaneRawValue instead")
    public var focusedEditorPaneRawValue: String { splitEditor.focusedEditorPaneRawValue }

    @available(*, deprecated, message: "Use splitEditor.primaryOpenTabRelativePaths instead")
    public var primaryOpenTabRelativePaths: [String] { splitEditor.primaryOpenTabRelativePaths }

    @available(*, deprecated, message: "Use splitEditor.primaryActiveTabRelativePath instead")
    public var primaryActiveTabRelativePath: String? { splitEditor.primaryActiveTabRelativePath }

    @available(*, deprecated, message: "Use splitEditor.secondaryOpenTabRelativePaths instead")
    public var secondaryOpenTabRelativePaths: [String] { splitEditor.secondaryOpenTabRelativePaths }

    @available(*, deprecated, message: "Use splitEditor.secondaryActiveTabRelativePath instead")
    public var secondaryActiveTabRelativePath: String? { splitEditor.secondaryActiveTabRelativePath }

    @available(*, deprecated, message: "Use fileTree.fileTreeExpandedRelativePaths instead")
    public var fileTreeExpandedRelativePaths: [String] { fileTree.fileTreeExpandedRelativePaths }

    @available(*, deprecated, message: "Use fileTree.languageOverridesByRelativePath instead")
    public var languageOverridesByRelativePath: [String: String] { fileTree.languageOverridesByRelativePath }
}
