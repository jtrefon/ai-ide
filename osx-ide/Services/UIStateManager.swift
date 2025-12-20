//
//  UIStateManager.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//

import SwiftUI
import Combine
import AppKit

/// Manages UI state and layout preferences
@MainActor
class UIStateManager: ObservableObject {
    // MARK: - Layout State
    
    @Published var isSidebarVisible: Bool = true
    @Published var sidebarWidth: Double = 250
    @Published var terminalHeight: Double = 200
    @Published var chatPanelWidth: Double = 300
    
    // MARK: - Editor State
    
    @Published var showLineNumbers: Bool = true
    @Published var wordWrap: Bool = false
    @Published var minimapVisible: Bool = false
    @Published var fontSize: Double = 14
    @Published var fontFamily: String = "SF Mono"
    
    // MARK: - Theme State
    
    @Published var selectedTheme: AppTheme = .system
    @Published var isDarkMode: Bool = false
    
    // MARK: - View State
    
    @Published var activeView: ActiveView = .editor
    @Published var isLoading: Bool = false
    @Published var isFullScreen: Bool = false
    @Published var windowTitle: String = "OSX IDE"
    
    // MARK: - Settings
    
    private let uiService: UIService
    private let userDefaults = UserDefaults.standard
    
    private let sidebarWidthKey = "SidebarWidth"
    private let terminalHeightKey = "TerminalHeight"
    private let chatPanelWidthKey = "ChatPanelWidth"
    private let fontSizeKey = "FontSize"
    private let fontFamilyKey = "FontFamily"
    private let showLineNumbersKey = "ShowLineNumbers"
    private let wordWrapKey = "WordWrap"
    private let minimapVisibleKey = "MinimapVisible"
    
    init(uiService: UIService) {
        self.uiService = uiService
        loadSettings()
        updateTheme()
    }
    
    // MARK: - Layout Management
    
    func toggleSidebar() {
        isSidebarVisible.toggle()
        uiService.setSidebarVisible(isSidebarVisible)
    }
    
    func setSidebarVisible(_ visible: Bool) {
        isSidebarVisible = visible
        uiService.setSidebarVisible(visible)
    }
    
    func updateSidebarWidth(_ width: Double) {
        sidebarWidth = max(AppConstants.Layout.minSidebarWidth, min(AppConstants.Layout.maxSidebarWidth, width))
        userDefaults.set(sidebarWidth, forKey: sidebarWidthKey)
    }
    
    func updateTerminalHeight(_ height: Double) {
        terminalHeight = max(AppConstants.Layout.minTerminalHeight, min(AppConstants.Layout.maxTerminalHeight, height))
        userDefaults.set(terminalHeight, forKey: terminalHeightKey)
    }
    
    func updateChatPanelWidth(_ width: Double) {
        chatPanelWidth = max(AppConstants.Layout.minChatPanelWidth, min(AppConstants.Layout.maxChatPanelWidth, width))
        userDefaults.set(chatPanelWidth, forKey: chatPanelWidthKey)
    }
    
    // MARK: - Editor Settings
    
    func toggleLineNumbers() {
        showLineNumbers.toggle()
        uiService.setShowLineNumbers(showLineNumbers)
    }
    
    func setShowLineNumbers(_ show: Bool) {
        showLineNumbers = show
        uiService.setShowLineNumbers(show)
    }
    
    func toggleWordWrap() {
        wordWrap.toggle()
        uiService.setWordWrap(wordWrap)
    }
    
    func setWordWrap(_ wrap: Bool) {
        wordWrap = wrap
        uiService.setWordWrap(wrap)
    }
    
    func toggleMinimap() {
        minimapVisible.toggle()
        uiService.setMinimapVisible(minimapVisible)
    }
    
    func setMinimapVisible(_ visible: Bool) {
        minimapVisible = visible
        uiService.setMinimapVisible(visible)
    }
    
    func updateFontSize(_ size: Double) {
        guard size >= AppConstants.Editor.minFontSize && size <= AppConstants.Editor.maxFontSize else { return }
        fontSize = size
        uiService.setFontSize(size)
    }
    
    func updateFontFamily(_ family: String) {
        fontFamily = family
        uiService.setFontFamily(family)
    }
    
    // MARK: - Theme Management
    
    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
        uiService.setTheme(theme)
        updateTheme()
    }
    
    private func updateTheme() {
        switch selectedTheme {
        case .light:
            isDarkMode = false
        case .dark:
            isDarkMode = true
        case .system:
            // Safely determine system appearance with fallback
            if let app = NSApp {
                let appearanceName = app.effectiveAppearance.name
                isDarkMode = appearanceName == .darkAqua
            } else {
                // Fallback: use current trait collection if app not available
                isDarkMode = false // Default to light mode as safe fallback
            }
        }
    }
    
    // MARK: - View State Management
    
    func setActiveView(_ view: ActiveView) {
        activeView = view
    }
    
    func setLoading(_ loading: Bool) {
        isLoading = loading
    }
    
    func toggleFullScreen() {
        isFullScreen.toggle()
        // This would be handled by the window controller
    }
    
    func updateWindowTitle(_ title: String) {
        windowTitle = title
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        // Load from UIService
        selectedTheme = uiService.selectedTheme
        fontSize = uiService.fontSize
        fontFamily = uiService.fontFamily
        showLineNumbers = uiService.showLineNumbers
        wordWrap = uiService.wordWrap
        minimapVisible = uiService.minimapVisible
        
        // Load layout settings
        sidebarWidth = userDefaults.double(forKey: sidebarWidthKey)
        if sidebarWidth == 0 { sidebarWidth = AppConstants.Layout.defaultSidebarWidth }
        
        terminalHeight = userDefaults.double(forKey: terminalHeightKey)
        if terminalHeight == 0 { terminalHeight = AppConstants.Layout.defaultTerminalHeight }
        
        chatPanelWidth = userDefaults.double(forKey: chatPanelWidthKey)
        if chatPanelWidth == 0 { chatPanelWidth = AppConstants.Layout.defaultChatPanelWidth }
        
        updateTheme()
    }
    
    func resetToDefaults() {
        // Reset UI service
        uiService.resetToDefaults()
        
        // Reset local state
        isSidebarVisible = true
        sidebarWidth = 250
        terminalHeight = AppConstants.Layout.defaultTerminalHeight
        chatPanelWidth = AppConstants.Layout.defaultChatPanelWidth
        showLineNumbers = true
        wordWrap = false
        minimapVisible = false
        fontSize = AppConstants.Editor.defaultFontSize
        fontFamily = "SF Mono"
        selectedTheme = .system
        
        // Clear UserDefaults for layout settings
        userDefaults.removeObject(forKey: sidebarWidthKey)
        userDefaults.removeObject(forKey: terminalHeightKey)
        userDefaults.removeObject(forKey: chatPanelWidthKey)
        
        updateTheme()
    }
    
    // MARK: - Settings Export/Import
    
    func exportSettings() -> [String: Any] {
        var settings = uiService.exportSettings()
        settings["sidebarWidth"] = sidebarWidth
        settings["terminalHeight"] = terminalHeight
        settings["chatPanelWidth"] = chatPanelWidth
        return settings
    }
    
    func importSettings(_ settings: [String: Any]) {
        uiService.importSettings(settings)
        
        if let sidebarWidth = settings["sidebarWidth"] as? Double {
            updateSidebarWidth(sidebarWidth)
        }
        
        if let terminalHeight = settings["terminalHeight"] as? Double {
            updateTerminalHeight(terminalHeight)
        }
        
        if let chatPanelWidth = settings["chatPanelWidth"] as? Double {
            updateChatPanelWidth(chatPanelWidth)
        }
        
        loadSettings()
    }
}

/// UI State enums
enum ActiveView {
    case editor
    case terminal
    case chat
    case settings
}