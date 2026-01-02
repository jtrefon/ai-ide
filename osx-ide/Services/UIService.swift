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
    private let userDefaults = UserDefaults.standard
    
    init(errorManager: ErrorManagerProtocol) {
        self.errorManager = errorManager
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
        userDefaults.set(size, forKey: AppConstants.Storage.fontSizeKey)
    }
    
    /// Update font family
    func setFontFamily(_ family: String) {
        userDefaults.set(family, forKey: AppConstants.Storage.fontFamilyKey)
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
        EventBus.shared.publish(SidebarWidthChangedEvent(width: width))
    }
    
    /// Update terminal height
    func setTerminalHeight(_ height: Double) {
        EventBus.shared.publish(TerminalHeightChangedEvent(height: height))
    }
    
    /// Update chat panel width
    func setChatPanelWidth(_ width: Double) {
        EventBus.shared.publish(ChatPanelWidthChangedEvent(width: width))
    }
    
    // MARK: - Settings Persistence
    
    /// Load settings from UserDefaults
    func loadSettings() -> UISettings {
        let storedTheme: AppTheme = .system
        
        let storedFontSize = userDefaults.double(forKey: AppConstants.Storage.fontSizeKey)
        let fontSize = storedFontSize == 0 ? AppConstants.Editor.defaultFontSize : storedFontSize
        
        let sidebarWidth = AppConstants.Layout.defaultSidebarWidth
        let terminalHeight = AppConstants.Layout.defaultTerminalHeight
        let chatPanelWidth = AppConstants.Layout.defaultChatPanelWidth
        
        let showLineNumbers: Bool = true
        let wordWrap: Bool = false
        let minimapVisible: Bool = false
        
        return UISettings(
            selectedTheme: storedTheme,
            fontSize: fontSize,
            fontFamily: userDefaults.string(forKey: AppConstants.Storage.fontFamilyKey) ?? "SF Mono",
            showLineNumbers: showLineNumbers,
            wordWrap: wordWrap,
            minimapVisible: minimapVisible,
            sidebarWidth: sidebarWidth,
            terminalHeight: terminalHeight,
            chatPanelWidth: chatPanelWidth
        )
    }
    
    /// Save settings to UserDefaults
    func saveSettings(_ settings: UISettings) {
        setTheme(settings.selectedTheme)
        setFontSize(settings.fontSize)
        setFontFamily(settings.fontFamily)
        setShowLineNumbers(settings.showLineNumbers)
        setWordWrap(settings.wordWrap)
        setMinimapVisible(settings.minimapVisible)
        setSidebarWidth(settings.sidebarWidth)
        setTerminalHeight(settings.terminalHeight)
        setChatPanelWidth(settings.chatPanelWidth)
    }
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        let keys = [
            AppConstants.Storage.fontSizeKey,
            AppConstants.Storage.fontFamilyKey
        ]
        keys.forEach { userDefaults.removeObject(forKey: $0) }
    }
    
    /// Export current settings
    func exportSettings() -> [String: Any] {
        let settings = loadSettings()
        return [
            "fontSize": settings.fontSize,
            "fontFamily": settings.fontFamily,
            "showLineNumbers": settings.showLineNumbers,
            "wordWrap": settings.wordWrap,
            "minimapVisible": settings.minimapVisible,
            "sidebarWidth": settings.sidebarWidth,
            "terminalHeight": settings.terminalHeight,
            "chatPanelWidth": settings.chatPanelWidth
        ]
    }
    
    /// Import settings
    func importSettings(_ settings: [String: Any]) {
        if let themeRaw = settings["theme"] as? String,
           let theme = AppTheme(rawValue: themeRaw) {
            setTheme(theme)
        }
        
        if let size = settings["fontSize"] as? Double {
            setFontSize(size)
        }
        
        if let family = settings["fontFamily"] as? String {
            setFontFamily(family)
        }
        
        if let show = settings["showLineNumbers"] as? Bool {
            setShowLineNumbers(show)
        }
        
        if let wrap = settings["wordWrap"] as? Bool {
            setWordWrap(wrap)
        }
        
        if let visible = settings["minimapVisible"] as? Bool {
            setMinimapVisible(visible)
        }
        
        if let width = settings["sidebarWidth"] as? Double {
            setSidebarWidth(width)
        }
        
        if let height = settings["terminalHeight"] as? Double {
            setTerminalHeight(height)
        }
        
        if let width = settings["chatPanelWidth"] as? Double {
            setChatPanelWidth(width)
        }
    }
}

struct UISettings {
    let selectedTheme: AppTheme
    let fontSize: Double
    let fontFamily: String
    let showLineNumbers: Bool
    let wordWrap: Bool
    let minimapVisible: Bool
    let sidebarWidth: Double
    let terminalHeight: Double
    let chatPanelWidth: Double
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
