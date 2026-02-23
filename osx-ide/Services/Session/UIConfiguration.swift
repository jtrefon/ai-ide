import Foundation

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
        sidebarWidth: Double = 300,
        terminalHeight: Double = 200,
        chatPanelWidth: Double = 200
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
