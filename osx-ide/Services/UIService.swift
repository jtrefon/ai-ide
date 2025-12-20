//
//  UIService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation
import SwiftUI

/// Persists UI settings to UserDefaults.
@MainActor
final class UIService {
    private let errorManager: ErrorManager
    private let userDefaults = UserDefaults.standard
    private let themeKey = "AppTheme"
    private let fontSizeKey = "FontSize"
    private let fontFamilyKey = "FontFamily"
    private let showLineNumbersKey = "ShowLineNumbers"
    private let wordWrapKey = "WordWrap"
    private let minimapVisibleKey = "MinimapVisible"
    
    init(errorManager: ErrorManager) {
        self.errorManager = errorManager
        loadSettings()
    }
    
    // MARK: - Theme Management
    
    /// Change application theme
    func setTheme(_ theme: AppTheme) {
        userDefaults.set(theme.rawValue, forKey: themeKey)
    }
    
    // MARK: - Font Settings
    
    /// Update font size
    func setFontSize(_ size: Double) {
        guard size >= 8 && size <= 72 else {
            errorManager.handle(.invalidFilePath("Font size must be between 8 and 72"))
            return
        }
        userDefaults.set(size, forKey: fontSizeKey)
    }
    
    /// Update font family
    func setFontFamily(_ family: String) {
        userDefaults.set(family, forKey: fontFamilyKey)
    }
    
    // MARK: - Editor Settings
    
    /// Toggle line numbers visibility
    func setShowLineNumbers(_ show: Bool) {
        userDefaults.set(show, forKey: showLineNumbersKey)
    }
    
    /// Toggle word wrap
    func setWordWrap(_ wrap: Bool) {
        userDefaults.set(wrap, forKey: wordWrapKey)
    }
    
    /// Toggle minimap visibility
    func setMinimapVisible(_ visible: Bool) {
        userDefaults.set(visible, forKey: minimapVisibleKey)
    }
    
    // MARK: - Settings Persistence
    
    /// Load settings from UserDefaults
    func loadSettings() -> UISettings {
        let storedTheme: AppTheme
        if let themeRaw = userDefaults.string(forKey: themeKey),
           let themeValue = AppTheme(rawValue: themeRaw) {
            storedTheme = themeValue
        } else {
            storedTheme = .system
        }
        
        let storedFontSize = userDefaults.double(forKey: fontSizeKey)
        let fontSize = storedFontSize == 0 ? 14 : storedFontSize
        
        return UISettings(
            selectedTheme: storedTheme,
            fontSize: fontSize,
            fontFamily: userDefaults.string(forKey: fontFamilyKey) ?? "SF Mono",
            showLineNumbers: userDefaults.bool(forKey: showLineNumbersKey),
            wordWrap: userDefaults.bool(forKey: wordWrapKey),
            minimapVisible: userDefaults.bool(forKey: minimapVisibleKey)
        )
    }
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        // Clear UserDefaults
        userDefaults.removeObject(forKey: themeKey)
        userDefaults.removeObject(forKey: fontSizeKey)
        userDefaults.removeObject(forKey: fontFamilyKey)
        userDefaults.removeObject(forKey: showLineNumbersKey)
        userDefaults.removeObject(forKey: wordWrapKey)
        userDefaults.removeObject(forKey: minimapVisibleKey)
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
            "minimapVisible": settings.minimapVisible
        ]
    }
    
    /// Import settings
    func importSettings(_ settings: [String: Any]) {
        if let themeRaw = settings["theme"] as? String,
           let theme = AppTheme(rawValue: themeRaw) {
            userDefaults.set(theme.rawValue, forKey: themeKey)
        }
        
        if let size = settings["fontSize"] as? Double {
            userDefaults.set(size, forKey: fontSizeKey)
        }
        
        if let family = settings["fontFamily"] as? String {
            userDefaults.set(family, forKey: fontFamilyKey)
        }
        
        if let show = settings["showLineNumbers"] as? Bool {
            userDefaults.set(show, forKey: showLineNumbersKey)
        }
        
        if let wrap = settings["wordWrap"] as? Bool {
            userDefaults.set(wrap, forKey: wordWrapKey)
        }
        
        if let visible = settings["minimapVisible"] as? Bool {
            userDefaults.set(visible, forKey: minimapVisibleKey)
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
}
