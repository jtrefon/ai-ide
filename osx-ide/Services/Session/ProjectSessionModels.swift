import Foundation
import CoreGraphics

// MARK: - Configuration Groupings

public struct UIConfiguration: Codable, Sendable {
    public var windowFrame: ProjectSession.WindowFrame?
    public var isSidebarVisible: Bool
    public var isTerminalVisible: Bool
    public var isAIChatVisible: Bool
    public var sidebarWidth: Double
    public var terminalHeight: Double
    public var chatPanelWidth: Double

    public init(
        windowFrame: ProjectSession.WindowFrame?,
        isSidebarVisible: Bool = true,
        isTerminalVisible: Bool = true,
        isAIChatVisible: Bool = true,
        sidebarWidth: Double = 250,
        terminalHeight: Double = 200,
        chatPanelWidth: Double = 300
    ) {
        self.windowFrame = windowFrame
        self.isSidebarVisible = isSidebarVisible
        self.isTerminalVisible = isTerminalVisible
        self.isAIChatVisible = isAIChatVisible
        self.sidebarWidth = sidebarWidth
        self.terminalHeight = terminalHeight
        self.chatPanelWidth = chatPanelWidth
    }
}

public struct EditorConfiguration: Codable, Sendable {
    public var selectedThemeRawValue: String
    public var showLineNumbers: Bool
    public var wordWrap: Bool
    public var minimapVisible: Bool
    public var showHiddenFilesInFileTree: Bool

    public init(
        selectedThemeRawValue: String = "system",
        showLineNumbers: Bool = true,
        wordWrap: Bool = false,
        minimapVisible: Bool = false,
        showHiddenFilesInFileTree: Bool = false
    ) {
        self.selectedThemeRawValue = selectedThemeRawValue
        self.showLineNumbers = showLineNumbers
        self.wordWrap = wordWrap
        self.minimapVisible = minimapVisible
        self.showHiddenFilesInFileTree = showHiddenFilesInFileTree
    }
}

public struct FileState: Codable, Sendable {
    public var lastOpenFileRelativePath: String?
    public var openTabRelativePaths: [String]
    public var activeTabRelativePath: String?

    public init(
        lastOpenFileRelativePath: String? = nil,
        openTabRelativePaths: [String] = [],
        activeTabRelativePath: String? = nil
    ) {
        self.lastOpenFileRelativePath = lastOpenFileRelativePath
        self.openTabRelativePaths = openTabRelativePaths
        self.activeTabRelativePath = activeTabRelativePath
    }
}

public struct SplitEditorState: Codable, Sendable {
    public var isSplitEditor: Bool
    public var splitAxisRawValue: String
    public var focusedEditorPaneRawValue: String
    public var primaryOpenTabRelativePaths: [String]
    public var primaryActiveTabRelativePath: String?
    public var secondaryOpenTabRelativePaths: [String]
    public var secondaryActiveTabRelativePath: String?

    public init(
        isSplitEditor: Bool = false,
        splitAxisRawValue: String = "vertical",
        focusedEditorPaneRawValue: String = "primary",
        primaryOpenTabRelativePaths: [String] = [],
        primaryActiveTabRelativePath: String? = nil,
        secondaryOpenTabRelativePaths: [String] = [],
        secondaryActiveTabRelativePath: String? = nil
    ) {
        self.isSplitEditor = isSplitEditor
        self.splitAxisRawValue = splitAxisRawValue
        self.focusedEditorPaneRawValue = focusedEditorPaneRawValue
        self.primaryOpenTabRelativePaths = primaryOpenTabRelativePaths
        self.primaryActiveTabRelativePath = primaryActiveTabRelativePath
        self.secondaryOpenTabRelativePaths = secondaryOpenTabRelativePaths
        self.secondaryActiveTabRelativePath = secondaryActiveTabRelativePath
    }
}

public struct FileTreeState: Codable, Sendable {
    public var fileTreeExpandedRelativePaths: [String]
    public var languageOverridesByRelativePath: [String: String]

    public init(
        fileTreeExpandedRelativePaths: [String] = [],
        languageOverridesByRelativePath: [String: String] = [:]
    ) {
        self.fileTreeExpandedRelativePaths = fileTreeExpandedRelativePaths
        self.languageOverridesByRelativePath = languageOverridesByRelativePath
    }
}

// MARK: - Main ProjectSession

public struct ProjectSession: Codable, Sendable {
    public struct WindowFrame: Codable, Sendable {
        public var originX: Double
        public var originY: Double
        public var width: Double
        public var height: Double

        enum CodingKeys: String, CodingKey {
            case originX = "x"
            case originY = "y"
            case width
            case height
        }

        public init(originX: Double, originY: Double, width: Double, height: Double) {
            self.originX = originX
            self.originY = originY
            self.width = width
            self.height = height
        }

        public init(rect: CGRect) {
            self.init(originX: rect.origin.x, originY: rect.origin.y, width: rect.size.width, height: rect.size.height)
        }

        public var rect: CGRect {
            CGRect(x: originX, y: originY, width: width, height: height)
        }
    }

    // MARK: - Properties (Grouped)

    public var ui: UIConfiguration
    public var editor: EditorConfiguration
    public var fileState: FileState
    public var splitEditor: SplitEditorState
    public var fileTree: FileTreeState
    public var aiModeRawValue: String

    // MARK: - Builder Pattern

    public init(
        ui: UIConfiguration,
        editor: EditorConfiguration,
        fileState: FileState,
        splitEditor: SplitEditorState,
        fileTree: FileTreeState,
        aiModeRawValue: String = "Chat"
    ) {
        self.ui = ui
        self.editor = editor
        self.fileState = fileState
        self.splitEditor = splitEditor
        self.fileTree = fileTree
        self.aiModeRawValue = aiModeRawValue
    }

    // MARK: - Convenience Initializer (Backward Compatibility)

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
        self.ui = UIConfiguration(
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

    // MARK: - Static Factory Methods

    public static func `default`() -> ProjectSession {
        ProjectSession(
            ui: UIConfiguration(windowFrame: nil),
            editor: EditorConfiguration(),
            fileState: FileState(),
            splitEditor: SplitEditorState(),
            fileTree: FileTreeState()
        )
    }

    public static func with(windowFrame: WindowFrame?) -> ProjectSessionBuilder {
        ProjectSessionBuilder().ui(UIConfiguration(windowFrame: windowFrame))
    }

    // MARK: - Computed Properties (Backward Compatibility)

    @available(*, deprecated, message: "Use ui.windowFrame instead")
    public var windowFrame: WindowFrame? { ui.windowFrame }

    @available(*, deprecated, message: "Use ui.isSidebarVisible instead")
    public var isSidebarVisible: Bool { ui.isSidebarVisible }

    @available(*, deprecated, message: "Use ui.isTerminalVisible instead")
    public var isTerminalVisible: Bool { ui.isTerminalVisible }

    @available(*, deprecated, message: "Use ui.isAIChatVisible instead")
    public var isAIChatVisible: Bool { ui.isAIChatVisible }

    @available(*, deprecated, message: "Use ui.sidebarWidth instead")
    public var sidebarWidth: Double { ui.sidebarWidth }

    @available(*, deprecated, message: "Use ui.terminalHeight instead")
    public var terminalHeight: Double { ui.terminalHeight }

    @available(*, deprecated, message: "Use ui.chatPanelWidth instead")
    public var chatPanelWidth: Double { ui.chatPanelWidth }

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

// MARK: - Builder Pattern

public class ProjectSessionBuilder {
    private var ui: UIConfiguration = UIConfiguration(windowFrame: nil)
    private var editor: EditorConfiguration = EditorConfiguration()
    private var fileState: FileState = FileState()
    private var splitEditor: SplitEditorState = SplitEditorState()
    private var fileTree: FileTreeState = FileTreeState()
    private var aiModeRawValue: String = "Chat"

    public init() {}

    public func ui(_ ui: UIConfiguration) -> ProjectSessionBuilder {
        self.ui = ui
        return self
    }

    public func editor(_ editor: EditorConfiguration) -> ProjectSessionBuilder {
        self.editor = editor
        return self
    }

    public func fileState(_ fileState: FileState) -> ProjectSessionBuilder {
        self.fileState = fileState
        return self
    }

    public func splitEditor(_ splitEditor: SplitEditorState) -> ProjectSessionBuilder {
        self.splitEditor = splitEditor
        return self
    }

    public func fileTree(_ fileTree: FileTreeState) -> ProjectSessionBuilder {
        self.fileTree = fileTree
        return self
    }

    public func aiMode(_ aiModeRawValue: String) -> ProjectSessionBuilder {
        self.aiModeRawValue = aiModeRawValue
        return self
    }

    public func build() -> ProjectSession {
        ProjectSession(
            ui: ui,
            editor: editor,
            fileState: fileState,
            splitEditor: splitEditor,
            fileTree: fileTree,
            aiModeRawValue: aiModeRawValue
        )
    }
}

// MARK: - Codable Implementation

extension ProjectSession {
    private enum CodingKeys: String, CodingKey {
        case ui
        case editor
        case fileState
        case splitEditor
        case fileTree
        case aiModeRawValue

        // Legacy keys for backward compatibility
        case windowFrame
        case isSidebarVisible
        case isTerminalVisible
        case isAIChatVisible
        case sidebarWidth
        case terminalHeight
        case chatPanelWidth
        case selectedThemeRawValue
        case showLineNumbers
        case wordWrap
        case minimapVisible
        case showHiddenFilesInFileTree
        case lastOpenFileRelativePath
        case openTabRelativePaths
        case activeTabRelativePath
        case isSplitEditor
        case splitAxisRawValue
        case focusedEditorPaneRawValue
        case primaryOpenTabRelativePaths
        case primaryActiveTabRelativePath
        case secondaryOpenTabRelativePaths
        case secondaryActiveTabRelativePath
        case fileTreeExpandedRelativePaths
        case languageOverridesByRelativePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try new format first
        if let ui = try container.decodeIfPresent(UIConfiguration.self, forKey: .ui),
           let editor = try container.decodeIfPresent(EditorConfiguration.self, forKey: .editor),
           let fileState = try container.decodeIfPresent(FileState.self, forKey: .fileState),
           let splitEditor = try container.decodeIfPresent(SplitEditorState.self, forKey: .splitEditor),
           let fileTree = try container.decodeIfPresent(FileTreeState.self, forKey: .fileTree) {

            self.ui = ui
            self.editor = editor
            self.fileState = fileState
            self.splitEditor = splitEditor
            self.fileTree = fileTree
            self.aiModeRawValue = try container.decodeIfPresent(String.self, forKey: .aiModeRawValue) ?? "Chat"
        } else {
            // Fallback to legacy format
            let windowFrame = try container.decodeIfPresent(WindowFrame.self, forKey: .windowFrame)

            let uiConfig = UIConfiguration(
                windowFrame: windowFrame,
                isSidebarVisible: try container.decodeIfPresent(Bool.self, forKey: .isSidebarVisible) ?? true,
                isTerminalVisible: try container.decodeIfPresent(Bool.self, forKey: .isTerminalVisible) ?? true,
                isAIChatVisible: try container.decodeIfPresent(Bool.self, forKey: .isAIChatVisible) ?? true,
                sidebarWidth: try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 250,
                terminalHeight: try container.decodeIfPresent(Double.self, forKey: .terminalHeight) ?? 200,
                chatPanelWidth: try container.decodeIfPresent(Double.self, forKey: .chatPanelWidth) ?? 300
            )

            let editorConfig = EditorConfiguration(
                selectedThemeRawValue: try container.decodeIfPresent(
                    String.self,
                    forKey: .selectedThemeRawValue
                ) ?? "system",
                showLineNumbers: try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true,
                wordWrap: try container.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? false,
                minimapVisible: try container.decodeIfPresent(Bool.self, forKey: .minimapVisible) ?? false,
                showHiddenFilesInFileTree: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .showHiddenFilesInFileTree
                ) ?? false
            )

            let fileStateConfig = FileState(
                lastOpenFileRelativePath: try container.decodeIfPresent(String.self, forKey: .lastOpenFileRelativePath),
                openTabRelativePaths: try container.decodeIfPresent([String].self, forKey: .openTabRelativePaths) ?? [],
                activeTabRelativePath: try container.decodeIfPresent(String.self, forKey: .activeTabRelativePath)
            )

            let splitEditorConfig = SplitEditorState(
                isSplitEditor: try container.decodeIfPresent(Bool.self, forKey: .isSplitEditor) ?? false,
                splitAxisRawValue: try container.decodeIfPresent(String.self, forKey: .splitAxisRawValue) ?? "vertical",
                focusedEditorPaneRawValue: try container.decodeIfPresent(
                    String.self,
                    forKey: .focusedEditorPaneRawValue
                ) ?? "primary",
                primaryOpenTabRelativePaths: try container.decodeIfPresent(
                    [String].self,
                    forKey: .primaryOpenTabRelativePaths
                ) ?? [],
                primaryActiveTabRelativePath: try container.decodeIfPresent(
                    String.self,
                    forKey: .primaryActiveTabRelativePath
                ),
                secondaryOpenTabRelativePaths: try container.decodeIfPresent(
                    [String].self,
                    forKey: .secondaryOpenTabRelativePaths
                ) ?? [],
                secondaryActiveTabRelativePath: try container.decodeIfPresent(String.self, forKey: .secondaryActiveTabRelativePath)
            )

            let fileTreeConfig = FileTreeState(
                fileTreeExpandedRelativePaths: try container.decodeIfPresent([String].self, forKey: .fileTreeExpandedRelativePaths) ?? [],
                languageOverridesByRelativePath: try container.decodeIfPresent([String: String].self, forKey: .languageOverridesByRelativePath) ?? [:]
            )

            self.ui = uiConfig
            self.editor = editorConfig
            self.fileState = fileStateConfig
            self.splitEditor = splitEditorConfig
            self.fileTree = fileTreeConfig
            self.aiModeRawValue = try container.decodeIfPresent(String.self, forKey: .aiModeRawValue) ?? "Chat"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(ui, forKey: .ui)
        try container.encode(editor, forKey: .editor)
        try container.encode(fileState, forKey: .fileState)
        try container.encode(splitEditor, forKey: .splitEditor)
        try container.encode(fileTree, forKey: .fileTree)
        try container.encode(aiModeRawValue, forKey: .aiModeRawValue)
    }
}
