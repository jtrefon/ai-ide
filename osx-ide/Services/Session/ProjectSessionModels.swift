import Foundation
import CoreGraphics

public struct ProjectSession: Codable, Sendable {
    public struct WindowFrame: Codable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public init(rect: CGRect) {
            self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
        }

        public var rect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    public var windowFrame: WindowFrame?

    public var isSidebarVisible: Bool
    public var isTerminalVisible: Bool
    public var isAIChatVisible: Bool
    public var sidebarWidth: Double
    public var terminalHeight: Double
    public var chatPanelWidth: Double

    public var selectedThemeRawValue: String

    public var showLineNumbers: Bool
    public var wordWrap: Bool
    public var minimapVisible: Bool

    public var showHiddenFilesInFileTree: Bool

    public var aiModeRawValue: String

    public var lastOpenFileRelativePath: String?

    public var openTabRelativePaths: [String]
    public var activeTabRelativePath: String?

    public var isSplitEditor: Bool
    public var splitAxisRawValue: String
    public var focusedEditorPaneRawValue: String

    public var primaryOpenTabRelativePaths: [String]
    public var primaryActiveTabRelativePath: String?
    public var secondaryOpenTabRelativePaths: [String]
    public var secondaryActiveTabRelativePath: String?

    public var fileTreeExpandedRelativePaths: [String]

    public var languageOverridesByRelativePath: [String: String]

    private enum CodingKeys: String, CodingKey {
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
        case aiModeRawValue
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
        self.windowFrame = windowFrame
        self.isSidebarVisible = isSidebarVisible
        self.isTerminalVisible = isTerminalVisible
        self.isAIChatVisible = isAIChatVisible
        self.sidebarWidth = sidebarWidth
        self.terminalHeight = terminalHeight
        self.chatPanelWidth = chatPanelWidth
        self.selectedThemeRawValue = selectedThemeRawValue
        self.showLineNumbers = showLineNumbers
        self.wordWrap = wordWrap
        self.minimapVisible = minimapVisible
        self.showHiddenFilesInFileTree = showHiddenFilesInFileTree
        self.aiModeRawValue = aiModeRawValue
        self.lastOpenFileRelativePath = lastOpenFileRelativePath
        self.openTabRelativePaths = openTabRelativePaths
        self.activeTabRelativePath = activeTabRelativePath

        self.isSplitEditor = isSplitEditor
        self.splitAxisRawValue = splitAxisRawValue
        self.focusedEditorPaneRawValue = focusedEditorPaneRawValue
        self.primaryOpenTabRelativePaths = primaryOpenTabRelativePaths
        self.primaryActiveTabRelativePath = primaryActiveTabRelativePath
        self.secondaryOpenTabRelativePaths = secondaryOpenTabRelativePaths
        self.secondaryActiveTabRelativePath = secondaryActiveTabRelativePath

        self.fileTreeExpandedRelativePaths = fileTreeExpandedRelativePaths

        self.languageOverridesByRelativePath = languageOverridesByRelativePath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        windowFrame = try c.decodeIfPresent(WindowFrame.self, forKey: .windowFrame)

        isSidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .isSidebarVisible) ?? true
        isTerminalVisible = try c.decodeIfPresent(Bool.self, forKey: .isTerminalVisible) ?? true
        isAIChatVisible = try c.decodeIfPresent(Bool.self, forKey: .isAIChatVisible) ?? true

        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 250
        terminalHeight = try c.decodeIfPresent(Double.self, forKey: .terminalHeight) ?? 200
        chatPanelWidth = try c.decodeIfPresent(Double.self, forKey: .chatPanelWidth) ?? 300

        selectedThemeRawValue = try c.decodeIfPresent(String.self, forKey: .selectedThemeRawValue) ?? "system"

        showLineNumbers = try c.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
        wordWrap = try c.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? false
        minimapVisible = try c.decodeIfPresent(Bool.self, forKey: .minimapVisible) ?? false

        showHiddenFilesInFileTree = try c.decodeIfPresent(Bool.self, forKey: .showHiddenFilesInFileTree) ?? false

        aiModeRawValue = try c.decodeIfPresent(String.self, forKey: .aiModeRawValue) ?? "Chat"

        lastOpenFileRelativePath = try c.decodeIfPresent(String.self, forKey: .lastOpenFileRelativePath)
        openTabRelativePaths = try c.decodeIfPresent([String].self, forKey: .openTabRelativePaths) ?? []
        activeTabRelativePath = try c.decodeIfPresent(String.self, forKey: .activeTabRelativePath)

        isSplitEditor = try c.decodeIfPresent(Bool.self, forKey: .isSplitEditor) ?? false
        splitAxisRawValue = try c.decodeIfPresent(String.self, forKey: .splitAxisRawValue) ?? "vertical"
        focusedEditorPaneRawValue = try c.decodeIfPresent(String.self, forKey: .focusedEditorPaneRawValue) ?? "primary"

        primaryOpenTabRelativePaths = try c.decodeIfPresent([String].self, forKey: .primaryOpenTabRelativePaths) ?? []
        primaryActiveTabRelativePath = try c.decodeIfPresent(String.self, forKey: .primaryActiveTabRelativePath)
        secondaryOpenTabRelativePaths = try c.decodeIfPresent([String].self, forKey: .secondaryOpenTabRelativePaths) ?? []
        secondaryActiveTabRelativePath = try c.decodeIfPresent(String.self, forKey: .secondaryActiveTabRelativePath)

        fileTreeExpandedRelativePaths = try c.decodeIfPresent([String].self, forKey: .fileTreeExpandedRelativePaths) ?? []

        languageOverridesByRelativePath = try c.decodeIfPresent([String: String].self, forKey: .languageOverridesByRelativePath) ?? [:]
    }
}
