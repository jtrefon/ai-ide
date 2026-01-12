//
//  UIService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation
import SwiftUI

/// Persists global UI settings to UserDefaults.
@MainActor
final class UIService: UIServiceProtocol {
    private let errorManager: ErrorManagerProtocol
    private let eventBus: EventBusProtocol
    private let settingsStore = SettingsStore(userDefaults: .standard)
    
    init(errorManager: ErrorManagerProtocol, eventBus: EventBusProtocol) {
        self.errorManager = errorManager
        self.eventBus = eventBus
    }
    
    // MARK: - Theme Management
    
    /// Change application theme
    func setTheme(_ theme: AppTheme) {
        // Project-scoped setting. Persisted via .ide/session.json
    }
    
    // MARK: - Font Settings
    
    /// Update font size
    func setFontSize(_ size: Double) {
        guard size >= AppConstants.Editor.minFontSize && size <= AppConstants.Editor.maxFontSize else {
            errorManager.handle(.invalidFilePath("Font size must be between \(AppConstants.Editor.minFontSize) and \(AppConstants.Editor.maxFontSize)"))
            return
        }
        settingsStore.set(size, forKey: AppConstants.Storage.fontSizeKey)
    }
    
    /// Update font family
    func setFontFamily(_ family: String) {
        settingsStore.set(family, forKey: AppConstants.Storage.fontFamilyKey)
    }

    // MARK: - Indentation

    func setIndentationStyle(_ style: IndentationStyle) {
        settingsStore.set(style.rawValue, forKey: AppConstants.Storage.indentationStyleKey)
    }

    func setCliTimeoutSeconds(_ seconds: Double) {
        let clamped = max(1, min(300, seconds))
        settingsStore.set(clamped, forKey: AppConstants.Storage.cliTimeoutSecondsKey)
    }
    
    // MARK: - Editor Settings
    
    /// Toggle line numbers visibility
    func setShowLineNumbers(_ show: Bool) {
        // Project-scoped setting. Persisted via .ide/session.json
    }
    
    /// Toggle word wrap
    func setWordWrap(_ wrap: Bool) {
        // Project-scoped setting. Persisted via .ide/session.json
    }
    
    /// Toggle minimap visibility
    func setMinimapVisible(_ visible: Bool) {
        // Project-scoped setting. Persisted via .ide/session.json
    }
    
    // MARK: - Layout Settings
    
    /// Update sidebar width
    func setSidebarWidth(_ width: Double) {
        eventBus.publish(SidebarWidthChangedEvent(width: width))
    }
    
    /// Update terminal height
    func setTerminalHeight(_ height: Double) {
        eventBus.publish(TerminalHeightChangedEvent(height: height))
    }
    
    /// Update chat panel width
    func setChatPanelWidth(_ width: Double) {
        eventBus.publish(ChatPanelWidthChangedEvent(width: width))
    }
    
    // MARK: - Terminal Settings
    
    /// Update terminal font size
    func setTerminalFontSize(_ size: Double) {
        settingsStore.set(size, forKey: "terminalFontSize")
    }
    
    /// Update terminal font family
    func setTerminalFontFamily(_ family: String) {
        settingsStore.set(family, forKey: "terminalFontFamily")
    }
    
    /// Update terminal foreground color
    func setTerminalForegroundColor(_ color: String) {
        settingsStore.set(color, forKey: "terminalForegroundColor")
    }
    
    /// Update terminal background color
    func setTerminalBackgroundColor(_ color: String) {
        settingsStore.set(color, forKey: "terminalBackgroundColor")
    }
    
    /// Update terminal shell
    func setTerminalShell(_ shell: String) {
        settingsStore.set(shell, forKey: "terminalShell")
    }
    
    // MARK: - Settings Persistence
    
    /// Load settings from UserDefaults
    func loadSettings() -> UISettings {
        let storedTheme: AppTheme = .system
        
        let storedFontSize = settingsStore.double(forKey: AppConstants.Storage.fontSizeKey)
        let fontSize = storedFontSize == 0 ? AppConstants.Editor.defaultFontSize : storedFontSize
        
        let sidebarWidth = AppConstants.Layout.defaultSidebarWidth
        let terminalHeight = AppConstants.Layout.defaultTerminalHeight
        let chatPanelWidth = AppConstants.Layout.defaultChatPanelWidth
        
        let showLineNumbers: Bool = true
        let wordWrap: Bool = false
        let minimapVisible: Bool = false

        let indentationStyle = IndentationStyle.current(userDefaults: .standard)

        let storedCliTimeout = settingsStore.double(forKey: AppConstants.Storage.cliTimeoutSecondsKey)
        let cliTimeoutSeconds = storedCliTimeout == 0 ? 30 : storedCliTimeout
        
        // Load terminal settings
        let terminalFontSize = settingsStore.double(forKey: "terminalFontSize")
        let terminalFontSizeValue = terminalFontSize == 0 ? 12 : terminalFontSize
        let terminalFontFamily = settingsStore.string(forKey: "terminalFontFamily") ?? "SF Mono"
        let terminalForegroundColor = settingsStore.string(forKey: "terminalForegroundColor") ?? "#00FF00"
        let terminalBackgroundColor = settingsStore.string(forKey: "terminalBackgroundColor") ?? "#000000"
        let terminalShell = settingsStore.string(forKey: "terminalShell") ?? "/bin/zsh"
        
        return UISettings(
            selectedTheme: storedTheme,
            fontSize: fontSize,
            fontFamily: settingsStore.string(forKey: AppConstants.Storage.fontFamilyKey) ?? AppConstants.Editor.defaultFontFamily,
            indentationStyle: indentationStyle,
            cliTimeoutSeconds: cliTimeoutSeconds,
            showLineNumbers: showLineNumbers,
            wordWrap: wordWrap,
            minimapVisible: minimapVisible,
            sidebarWidth: sidebarWidth,
            terminalHeight: terminalHeight,
            chatPanelWidth: chatPanelWidth,
            terminalFontSize: terminalFontSizeValue,
            terminalFontFamily: terminalFontFamily,
            terminalForegroundColor: terminalForegroundColor,
            terminalBackgroundColor: terminalBackgroundColor,
            terminalShell: terminalShell
        )
    }
    
    /// Save settings to UserDefaults
    func saveSettings(_ settings: UISettings) {
        setTheme(settings.selectedTheme)
        setFontSize(settings.fontSize)
        setFontFamily(settings.fontFamily)
        setIndentationStyle(settings.indentationStyle)
        setCliTimeoutSeconds(settings.cliTimeoutSeconds)
        setShowLineNumbers(settings.showLineNumbers)
        setWordWrap(settings.wordWrap)
        setMinimapVisible(settings.minimapVisible)
        setSidebarWidth(settings.sidebarWidth)
        setTerminalHeight(settings.terminalHeight)
        setChatPanelWidth(settings.chatPanelWidth)
        
        // Save terminal settings
        setTerminalFontSize(settings.terminalFontSize)
        setTerminalFontFamily(settings.terminalFontFamily)
        setTerminalForegroundColor(settings.terminalForegroundColor)
        setTerminalBackgroundColor(settings.terminalBackgroundColor)
        setTerminalShell(settings.terminalShell)
    }
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        let keys = [
            AppConstants.Storage.fontSizeKey,
            AppConstants.Storage.fontFamilyKey,
            AppConstants.Storage.indentationStyleKey,
            AppConstants.Storage.cliTimeoutSecondsKey
        ]
        keys.forEach { settingsStore.removeObject(forKey: $0) }
    }
    
    /// Export all settings as dictionary
    func exportSettings() -> [String: Any] {
        let settings = loadSettings()
        return [
            "selectedTheme": settings.selectedTheme.rawValue,
            "fontSize": settings.fontSize,
            "fontFamily": settings.fontFamily,
            "indentationStyle": settings.indentationStyle.rawValue,
            "cliTimeoutSeconds": settings.cliTimeoutSeconds,
            "showLineNumbers": settings.showLineNumbers,
            "wordWrap": settings.wordWrap,
            "minimapVisible": settings.minimapVisible,
            "sidebarWidth": settings.sidebarWidth,
            "terminalHeight": settings.terminalHeight,
            "chatPanelWidth": settings.chatPanelWidth,
            "terminalFontSize": settings.terminalFontSize,
            "terminalFontFamily": settings.terminalFontFamily,
            "terminalForegroundColor": settings.terminalForegroundColor,
            "terminalBackgroundColor": settings.terminalBackgroundColor,
            "terminalShell": settings.terminalShell
        ]
    }
    
    /// Import settings
    func importSettings(_ settings: [String: Any]) {
        applyTheme(from: settings)
        applyFontSize(from: settings)
        applyFontFamily(from: settings)
        applyIndentationStyle(from: settings)
        applyCliTimeoutSeconds(from: settings)
        applyShowLineNumbers(from: settings)
        applyWordWrap(from: settings)
        applyMinimapVisible(from: settings)
        applySidebarWidth(from: settings)
        applyTerminalHeight(from: settings)
        applyChatPanelWidth(from: settings)
        
        // Apply terminal settings
        applyTerminalFontSize(from: settings)
        applyTerminalFontFamily(from: settings)
        applyTerminalForegroundColor(from: settings)
        applyTerminalBackgroundColor(from: settings)
        applyTerminalShell(from: settings)
    }

    private func applyTheme(from settings: [String: Any]) {
        guard let themeRaw = settings["theme"] as? String,
              let theme = AppTheme(rawValue: themeRaw) else {
            return
        }
        setTheme(theme)
    }

    private func applyFontSize(from settings: [String: Any]) {
        guard let size = settings["fontSize"] as? Double else { return }
        setFontSize(size)
    }

    private func applyFontFamily(from settings: [String: Any]) {
        guard let family = settings["fontFamily"] as? String else { return }
        setFontFamily(family)
    }

    private func applyIndentationStyle(from settings: [String: Any]) {
        guard let raw = settings["indentationStyle"] as? String,
              let style = IndentationStyle(rawValue: raw) else {
            return
        }
        setIndentationStyle(style)
    }

    private func applyCliTimeoutSeconds(from settings: [String: Any]) {
        guard let timeout = settings["cliTimeoutSeconds"] as? Double else { return }
        setCliTimeoutSeconds(timeout)
    }

    private func applyShowLineNumbers(from settings: [String: Any]) {
        guard let show = settings["showLineNumbers"] as? Bool else { return }
        setShowLineNumbers(show)
    }

    private func applyWordWrap(from settings: [String: Any]) {
        guard let wrap = settings["wordWrap"] as? Bool else { return }
        setWordWrap(wrap)
    }

    private func applyMinimapVisible(from settings: [String: Any]) {
        guard let visible = settings["minimapVisible"] as? Bool else { return }
        setMinimapVisible(visible)
    }

    private func applySidebarWidth(from settings: [String: Any]) {
        guard let width = settings["sidebarWidth"] as? Double else { return }
        setSidebarWidth(width)
    }

    private func applyTerminalHeight(from settings: [String: Any]) {
        guard let height = settings["terminalHeight"] as? Double else { return }
        setTerminalHeight(height)
    }

    private func applyChatPanelWidth(from settings: [String: Any]) {
        guard let width = settings["chatPanelWidth"] as? Double else { return }
        setChatPanelWidth(width)
    }
    
    // MARK: - Terminal Settings Apply Methods
    
    private func applyTerminalFontSize(from settings: [String: Any]) {
        guard let size = settings["terminalFontSize"] as? Double else { return }
        setTerminalFontSize(size)
    }
    
    private func applyTerminalFontFamily(from settings: [String: Any]) {
        guard let family = settings["terminalFontFamily"] as? String else { return }
        setTerminalFontFamily(family)
    }
    
    private func applyTerminalForegroundColor(from settings: [String: Any]) {
        guard let color = settings["terminalForegroundColor"] as? String else { return }
        setTerminalForegroundColor(color)
    }
    
    private func applyTerminalBackgroundColor(from settings: [String: Any]) {
        guard let color = settings["terminalBackgroundColor"] as? String else { return }
        setTerminalBackgroundColor(color)
    }
    
    private func applyTerminalShell(from settings: [String: Any]) {
        guard let shell = settings["terminalShell"] as? String else { return }
        setTerminalShell(shell)
    }
}

struct UISettings {
    let selectedTheme: AppTheme
    let fontSize: Double
    let fontFamily: String
    let indentationStyle: IndentationStyle
    let cliTimeoutSeconds: Double
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

/// Application theme options
enum AppTheme: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
}
