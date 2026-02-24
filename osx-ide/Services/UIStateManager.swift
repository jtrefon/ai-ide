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

    @Published var isSidebarVisible: Bool = true {
        didSet { trackChange("isSidebarVisible", from: oldValue, to: isSidebarVisible) }
    }
    @Published var isTerminalVisible: Bool = true {
        didSet { trackChange("isTerminalVisible", from: oldValue, to: isTerminalVisible) }
    }
    @Published var isAIChatVisible: Bool = true {
        didSet { trackChange("isAIChatVisible", from: oldValue, to: isAIChatVisible) }
    }
    @Published var bottomPanelSelectedName: String = AppConstants.UI.internalTerminalPanelName {
        didSet { trackChange("bottomPanelSelectedName", from: oldValue, to: bottomPanelSelectedName) }
    }
    @Published var sidebarWidth: Double = AppConstants.Layout.defaultSidebarWidth {
        didSet { trackChange("sidebarWidth", from: oldValue, to: sidebarWidth) }
    }
    @Published var terminalHeight: Double = AppConstants.Layout.defaultTerminalHeight {
        didSet { trackChange("terminalHeight", from: oldValue, to: terminalHeight) }
    }
    @Published var chatPanelWidth: Double = AppConstants.Layout.defaultChatPanelWidth {
        didSet { trackChange("chatPanelWidth", from: oldValue, to: chatPanelWidth) }
    }

    // MARK: - Editor State

    @Published var showLineNumbers: Bool = true {
        didSet { trackChange("showLineNumbers", from: oldValue, to: showLineNumbers) }
    }
    @Published var wordWrap: Bool = false {
        didSet { trackChange("wordWrap", from: oldValue, to: wordWrap) }
    }
    @Published var minimapVisible: Bool = false {
        didSet { trackChange("minimapVisible", from: oldValue, to: minimapVisible) }
    }
    @Published var fontSize: Double = AppConstants.Editor.defaultFontSize {
        didSet { trackChange("fontSize", from: oldValue, to: fontSize) }
    }
    @Published var fontFamily: String = AppConstants.Editor.defaultFontFamily {
        didSet { trackChange("fontFamily", from: oldValue, to: fontFamily) }
    }
    @Published var indentationStyle: IndentationStyle = .tabs {
        didSet { trackChange("indentationStyle", from: String(describing: oldValue), to: String(describing: indentationStyle)) }
    }

    // MARK: - Terminal Settings

    @Published var terminalFontSize: Double = 12
    @Published var terminalFontFamily: String = "SF Mono"
    @Published var terminalForegroundColor: String = "#00FF00" // Green
    @Published var terminalBackgroundColor: String = "#000000" // Black
    @Published var terminalShell: String = "/bin/zsh"

    // MARK: - Agent Settings

    @Published var cliTimeoutSeconds: Double = 30
    @Published var agentMemoryEnabled: Bool = true
    @Published var agentQAReviewEnabled: Bool = false

    // MARK: - Theme State

    @Published var selectedTheme: AppTheme = .system
    @Published var isDarkMode: Bool = false

    // MARK: - Services

    private let uiService: UIServiceProtocol
    private let eventBus: EventBusProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Diagnostics
    
    private var changeCounts: [String: Int] = [:]
    private var lastChangeTime: [String: Date] = [:]

    init(uiService: UIServiceProtocol, eventBus: EventBusProtocol) {
        self.uiService = uiService
        self.eventBus = eventBus
        loadSettings()
        updateTheme()
        setupEventSubscriptions()
    }
    
    private func trackChange<T>(_ name: String, from: T, to: T) where T: Equatable {
        guard from != to else { return }
        
        let count = (changeCounts[name] ?? 0) + 1
        changeCounts[name] = count
        
        let now = Date()
        let lastTime = lastChangeTime[name]
        lastChangeTime[name] = now
        
        // Check for rapid changes (more than 5 changes in 1 second)
        if let last = lastTime, now.timeIntervalSince(last) < 1.0 && count > 5 {
            Swift.print("[DIAG] ⚠️ RAPID STATE CHANGE: \(name) changed \(count) times")
            Swift.print("[DIAG] Stack: \(Thread.callStackSymbols.prefix(3).joined(separator: "\n"))")
        }
        
        // Log every 10 changes
        if count % 10 == 0 {
            Swift.print("[DIAG] UIState.\(name) changed \(count) times")
        }
    }

    private func setupEventSubscriptions() {
        eventBus.subscribe(to: SidebarWidthChangedEvent.self) { [weak self] event in
            self?.sidebarWidth = event.width
        }.store(in: &cancellables)

        eventBus.subscribe(to: TerminalHeightChangedEvent.self) { [weak self] event in
            self?.terminalHeight = event.height
        }.store(in: &cancellables)

        eventBus.subscribe(to: ChatPanelWidthChangedEvent.self) { [weak self] event in
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

    func setIndentationStyle(_ style: IndentationStyle) {
        indentationStyle = style
        uiService.setIndentationStyle(style)
    }

    // MARK: - Terminal Settings

    func updateTerminalFontSize(_ size: Double) {
        guard size >= 8 && size <= 72 else { return }
        terminalFontSize = size
        uiService.setTerminalFontSize(size)
    }

    func updateTerminalFontFamily(_ family: String) {
        terminalFontFamily = family
        uiService.setTerminalFontFamily(family)
    }

    func updateTerminalForegroundColor(_ color: String) {
        terminalForegroundColor = color
        uiService.setTerminalForegroundColor(color)
    }

    func updateTerminalBackgroundColor(_ color: String) {
        terminalBackgroundColor = color
        uiService.setTerminalBackgroundColor(color)
    }

    func updateTerminalShell(_ shell: String) {
        terminalShell = shell
        uiService.setTerminalShell(shell)
    }

    // MARK: - Theme Management

    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
        uiService.setTheme(theme)
        updateTheme()
    }

    func setCliTimeoutSeconds(_ seconds: Double) {
        let clamped = max(1, min(300, seconds))
        cliTimeoutSeconds = clamped
        uiService.setCliTimeoutSeconds(clamped)
    }

    func setAgentMemoryEnabled(_ enabled: Bool) {
        agentMemoryEnabled = enabled
        uiService.setAgentMemoryEnabled(enabled)
    }

    func setAgentQAReviewEnabled(_ enabled: Bool) {
        agentQAReviewEnabled = enabled
        uiService.setAgentQAReviewEnabled(enabled)
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
        indentationStyle = settings.indentationStyle
        cliTimeoutSeconds = settings.cliTimeoutSeconds
        agentMemoryEnabled = settings.agentMemoryEnabled
        agentQAReviewEnabled = settings.agentQAReviewEnabled
        showLineNumbers = settings.showLineNumbers
        wordWrap = settings.wordWrap
        minimapVisible = settings.minimapVisible
        sidebarWidth = settings.sidebarWidth
        terminalHeight = settings.terminalHeight
        chatPanelWidth = settings.chatPanelWidth

        // Load terminal settings
        terminalFontSize = settings.terminalFontSize
        terminalFontFamily = settings.terminalFontFamily
        terminalForegroundColor = settings.terminalForegroundColor
        terminalBackgroundColor = settings.terminalBackgroundColor
        terminalShell = settings.terminalShell

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
        fontFamily = AppConstants.Editor.defaultFontFamily
        indentationStyle = .tabs
        cliTimeoutSeconds = 30
        agentMemoryEnabled = true
        selectedTheme = .system

        // Reset terminal settings to defaults
        terminalFontSize = 12
        terminalFontFamily = "SF Mono"
        terminalForegroundColor = "#00FF00" // Green
        terminalBackgroundColor = "#000000" // Black
        terminalShell = "/bin/zsh"

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
