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
    @Published var isTerminalVisible: Bool = true
    @Published var isAIChatVisible: Bool = true
    @Published var sidebarWidth: Double = AppConstants.Layout.defaultSidebarWidth
    @Published var terminalHeight: Double = AppConstants.Layout.defaultTerminalHeight
    @Published var chatPanelWidth: Double = AppConstants.Layout.defaultChatPanelWidth
    
    // MARK: - Editor State
    
    @Published var showLineNumbers: Bool = true
    @Published var wordWrap: Bool = false
    @Published var minimapVisible: Bool = false
    @Published var fontSize: Double = AppConstants.Editor.defaultFontSize
    @Published var fontFamily: String = "SF Mono"
    
    // MARK: - Theme State
    
    @Published var selectedTheme: AppTheme = .system
    @Published var isDarkMode: Bool = false
    
    // MARK: - Services
    
    private let uiService: UIServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(uiService: UIServiceProtocol) {
        self.uiService = uiService
        loadSettings()
        updateTheme()
        setupEventSubscriptions()
    }
    
    private func setupEventSubscriptions() {
        EventBus.shared.subscribe(to: SidebarWidthChangedEvent.self) { [weak self] event in
            self?.sidebarWidth = event.width
        }.store(in: &cancellables)
        
        EventBus.shared.subscribe(to: TerminalHeightChangedEvent.self) { [weak self] event in
            self?.terminalHeight = event.height
        }.store(in: &cancellables)
        
        EventBus.shared.subscribe(to: ChatPanelWidthChangedEvent.self) { [weak self] event in
            self?.chatPanelWidth = event.width
        }.store(in: &cancellables)
    }
    
    // MARK: - Layout Management
    
    func toggleSidebar() {
        isSidebarVisible.toggle()
    }
    
    func setSidebarVisible(_ visible: Bool) {
        isSidebarVisible = visible
    }

    func setTerminalVisible(_ visible: Bool) {
        isTerminalVisible = visible
    }

    func setAIChatVisible(_ visible: Bool) {
        isAIChatVisible = visible
    }
    
    func updateSidebarWidth(_ width: Double) {
        sidebarWidth = max(AppConstants.Layout.minSidebarWidth, min(AppConstants.Layout.maxSidebarWidth, width))
        uiService.setSidebarWidth(sidebarWidth)
    }
    
    func updateTerminalHeight(_ height: Double) {
        terminalHeight = max(AppConstants.Layout.minTerminalHeight, min(AppConstants.Layout.maxTerminalHeight, height))
        uiService.setTerminalHeight(terminalHeight)
    }
    
    func updateChatPanelWidth(_ width: Double) {
        chatPanelWidth = max(AppConstants.Layout.minChatPanelWidth, min(AppConstants.Layout.maxChatPanelWidth, width))
        uiService.setChatPanelWidth(chatPanelWidth)
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
            if let app = NSApp {
                let currentAppearance = app.effectiveAppearance
                isDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            } else {
                isDarkMode = false
            }
        }
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        let settings = uiService.loadSettings()
        selectedTheme = settings.selectedTheme
        fontSize = settings.fontSize
        fontFamily = settings.fontFamily
        showLineNumbers = settings.showLineNumbers
        wordWrap = settings.wordWrap
        minimapVisible = settings.minimapVisible
        sidebarWidth = settings.sidebarWidth
        terminalHeight = settings.terminalHeight
        chatPanelWidth = settings.chatPanelWidth
        
        updateTheme()
    }
    
    func resetToDefaults() {
        uiService.resetToDefaults()
        
        // Reset local state to defaults
        isSidebarVisible = true
        isTerminalVisible = true
        isAIChatVisible = true
        sidebarWidth = AppConstants.Layout.defaultSidebarWidth
        terminalHeight = AppConstants.Layout.defaultTerminalHeight
        chatPanelWidth = AppConstants.Layout.defaultChatPanelWidth
        showLineNumbers = true
        wordWrap = false
        minimapVisible = false
        fontSize = AppConstants.Editor.defaultFontSize
        fontFamily = "SF Mono"
        selectedTheme = .system
        
        updateTheme()
    }
    
    // MARK: - Settings Export/Import
    
    func exportSettings() -> [String: Any] {
        return uiService.exportSettings()
    }
    
    func importSettings(_ settings: [String: Any]) {
        uiService.importSettings(settings)
        loadSettings() // Refresh local state
    }
}
