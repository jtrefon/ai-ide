import Foundation

@MainActor
protocol UIServiceProtocol {
    func loadSettings() -> UISettings
    func saveSettings(_ settings: UISettings)
    func resetToDefaults()
    func setTheme(_ theme: AppTheme)
    func setFontSize(_ size: Double)
    func setFontFamily(_ family: String)
    func setIndentationStyle(_ style: IndentationStyle)
    func setShowLineNumbers(_ show: Bool)
    func setWordWrap(_ wrap: Bool)
    func setMinimapVisible(_ visible: Bool)
    func setSidebarWidth(_ width: Double)
    func setTerminalHeight(_ height: Double)
    func setChatPanelWidth(_ width: Double)
    func exportSettings() -> [String: Any]
    func importSettings(_ settings: [String: Any])
}
