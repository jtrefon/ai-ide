import Foundation

struct UISettings {
    let selectedTheme: AppTheme
    let fontSize: Double
    let fontFamily: String
    let indentationStyle: IndentationStyle
    let cliTimeoutSeconds: Double
    let agentMemoryEnabled: Bool
    let showLineNumbers: Bool
    let wordWrap: Bool
    let minimapVisible: Bool
    let sidebarWidth: Double
    let terminalHeight: Double
    let chatPanelWidth: Double

    // Terminal settings
    let terminalFontSize: Double
    let terminalFontFamily: String
    let terminalForegroundColor: String
    let terminalBackgroundColor: String
    let terminalShell: String
}
