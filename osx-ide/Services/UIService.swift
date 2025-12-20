//
//  UIService.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import Foundation
import SwiftUI

/// Manages UI state and layout preferences
@MainActor
class UIService: ObservableObject {
    @Published var isSidebarVisible = true
    @Published var selectedTheme: AppTheme = .system
    @Published var fontSize: Double = 14
    @Published var fontFamily: String = "SF Mono"
    @Published var showLineNumbers = true
    @Published var wordWrap = false
    @Published var minimapVisible = false
    
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
    
    // MARK: - Sidebar Management
    
    /// Toggle sidebar visibility
    func toggleSidebar() {
        isSidebarVisible.toggle()
    }
    
    /// Set sidebar visibility
    func setSidebarVisible(_ visible: Bool) {
        isSidebarVisible = visible
    }
    
    // MARK: - Theme Management
    
    /// Change application theme
    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
        userDefaults.set(theme.rawValue, forKey: themeKey)
    }
    
    // MARK: - Font Settings
    
    /// Update font size
    func setFontSize(_ size: Double) {
        guard size >= 8 && size <= 72 else {
            errorManager.handle(.invalidFilePath("Font size must be between 8 and 72"))
            return
        }
        fontSize = size
        userDefaults.set(size, forKey: fontSizeKey)
    }
    
    /// Update font family
    func setFontFamily(_ family: String) {
        fontFamily = family
        userDefaults.set(family, forKey: fontFamilyKey)
    }
    
    // MARK: - Editor Settings
    
    /// Toggle line numbers visibility
    func setShowLineNumbers(_ show: Bool) {
        showLineNumbers = show
        userDefaults.set(show, forKey: showLineNumbersKey)
    }
    
    /// Toggle word wrap
    func setWordWrap(_ wrap: Bool) {
        wordWrap = wrap
        userDefaults.set(wrap, forKey: wordWrapKey)
    }
    
    /// Toggle minimap visibility
    func setMinimapVisible(_ visible: Bool) {
        minimapVisible = visible
        userDefaults.set(visible, forKey: minimapVisibleKey)
    }
    
    // MARK: - Settings Persistence
    
    /// Load settings from UserDefaults
    private func loadSettings() {
        if let themeRaw = userDefaults.string(forKey: themeKey),
           let theme = AppTheme(rawValue: themeRaw) {
            selectedTheme = theme
        }
        
        fontSize = userDefaults.double(forKey: fontSizeKey)
        if fontSize == 0 { fontSize = 14 } // Default if not set
        
        fontFamily = userDefaults.string(forKey: fontFamilyKey) ?? "SF Mono"
        showLineNumbers = userDefaults.bool(forKey: showLineNumbersKey)
        wordWrap = userDefaults.bool(forKey: wordWrapKey)
        minimapVisible = userDefaults.bool(forKey: minimapVisibleKey)
    }
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        selectedTheme = .system
        fontSize = 14
        fontFamily = "SF Mono"
        showLineNumbers = true
        wordWrap = false
        minimapVisible = false
        
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
        return [
            "theme": selectedTheme.rawValue,
            "fontSize": fontSize,
            "fontFamily": fontFamily,
            "showLineNumbers": showLineNumbers,
            "wordWrap": wordWrap,
            "minimapVisible": minimapVisible
        ]
    }
    
    /// Import settings
    func importSettings(_ settings: [String: Any]) {
        if let themeRaw = settings["theme"] as? String,
           let theme = AppTheme(rawValue: themeRaw) {
            selectedTheme = theme
        }
        
        if let size = settings["fontSize"] as? Double {
            fontSize = size
        }
        
        if let family = settings["fontFamily"] as? String {
            fontFamily = family
        }
        
        if let show = settings["showLineNumbers"] as? Bool {
            showLineNumbers = show
        }
        
        if let wrap = settings["wordWrap"] as? Bool {
            wordWrap = wrap
        }
        
        if let visible = settings["minimapVisible"] as? Bool {
            minimapVisible = visible
        }
        
        // Save imported settings
        saveSettings()
    }
    
    /// Save current settings
    private func saveSettings() {
        userDefaults.set(selectedTheme.rawValue, forKey: themeKey)
        userDefaults.set(fontSize, forKey: fontSizeKey)
        userDefaults.set(fontFamily, forKey: fontFamilyKey)
        userDefaults.set(showLineNumbers, forKey: showLineNumbersKey)
        userDefaults.set(wordWrap, forKey: wordWrapKey)
        userDefaults.set(minimapVisible, forKey: minimapVisibleKey)
    }
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
