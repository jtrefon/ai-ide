//
//  UIService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation
import SwiftUI

/// Persists UI settings and layout state to UserDefaults.
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
        userDefaults.set(theme.rawValue, forKey: AppConstants.Storage.themeKey)
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
        userDefaults.set(show, forKey: AppConstants.Storage.showLineNumbersKey)
    }
    
    /// Toggle word wrap
    func setWordWrap(_ wrap: Bool) {
        userDefaults.set(wrap, forKey: AppConstants.Storage.wordWrapKey)
    }
    
    /// Toggle minimap visibility
    func setMinimapVisible(_ visible: Bool) {
        userDefaults.set(visible, forKey: AppConstants.Storage.minimapVisibleKey)
    }
    
    // MARK: - Layout Settings
    
    /// Update sidebar width
    func setSidebarWidth(_ width: Double) {
        userDefaults.set(width, forKey: AppConstants.Storage.sidebarWidthKey)
        EventBus.shared.publish(SidebarWidthChangedEvent(width: width))
    }
    
    /// Update terminal height
    func setTerminalHeight(_ height: Double) {
        userDefaults.set(height, forKey: AppConstants.Storage.terminalHeightKey)
        EventBus.shared.publish(TerminalHeightChangedEvent(height: height))
    }
    
    /// Update chat panel width
    func setChatPanelWidth(_ width: Double) {
        userDefaults.set(width, forKey: AppConstants.Storage.chatPanelWidthKey)
        EventBus.shared.publish(ChatPanelWidthChangedEvent(width: width))
    }
    
    // MARK: - Settings Persistence
    
    /// Load settings from UserDefaults
    func loadSettings() -> UISettings {
        let storedTheme: AppTheme
        if let themeRaw = userDefaults.string(forKey: AppConstants.Storage.themeKey),
           let themeValue = AppTheme(rawValue: themeRaw) {
            storedTheme = themeValue
        } else {
            storedTheme = .system
        }
        
        let storedFontSize = userDefaults.double(forKey: AppConstants.Storage.fontSizeKey)
        let fontSize = storedFontSize == 0 ? AppConstants.Editor.defaultFontSize : storedFontSize
        
        let sidebarWidth = userDefaults.double(forKey: AppConstants.Storage.sidebarWidthKey)
        let terminalHeight = userDefaults.double(forKey: AppConstants.Storage.terminalHeightKey)
        let chatPanelWidth = userDefaults.double(forKey: AppConstants.Storage.chatPanelWidthKey)

        let showLineNumbers: Bool = userDefaults.object(forKey: AppConstants.Storage.showLineNumbersKey) == nil
            ? true
            : userDefaults.bool(forKey: AppConstants.Storage.showLineNumbersKey)

        let wordWrap: Bool = userDefaults.object(forKey: AppConstants.Storage.wordWrapKey) == nil
            ? false
            : userDefaults.bool(forKey: AppConstants.Storage.wordWrapKey)

        let minimapVisible: Bool = userDefaults.object(forKey: AppConstants.Storage.minimapVisibleKey) == nil
            ? false
            : userDefaults.bool(forKey: AppConstants.Storage.minimapVisibleKey)
        
        return UISettings(
            selectedTheme: storedTheme,
            fontSize: fontSize,
            fontFamily: userDefaults.string(forKey: AppConstants.Storage.fontFamilyKey) ?? "SF Mono",
            showLineNumbers: showLineNumbers,
            wordWrap: wordWrap,
            minimapVisible: minimapVisible,
            sidebarWidth: sidebarWidth == 0 ? AppConstants.Layout.defaultSidebarWidth : sidebarWidth,
            terminalHeight: terminalHeight == 0 ? AppConstants.Layout.defaultTerminalHeight : terminalHeight,
            chatPanelWidth: chatPanelWidth == 0 ? AppConstants.Layout.defaultChatPanelWidth : chatPanelWidth
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
            AppConstants.Storage.themeKey,
            AppConstants.Storage.fontSizeKey,
            AppConstants.Storage.fontFamilyKey,
            AppConstants.Storage.showLineNumbersKey,
            AppConstants.Storage.wordWrapKey,
            AppConstants.Storage.minimapVisibleKey,
            AppConstants.Storage.sidebarWidthKey,
            AppConstants.Storage.terminalHeightKey,
            AppConstants.Storage.chatPanelWidthKey
        ]
        keys.forEach { userDefaults.removeObject(forKey: $0) }
    }
    
    /// Export current settings
    func exportSettings() -> [String: Any] {
        let settings = loadSettings()
        return [
            "theme": settings.selectedTheme.rawValue,
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
