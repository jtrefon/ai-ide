//
//  AppConstants.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//

import Foundation
import AppKit
import SwiftUI

enum IndentationStyle: String, CaseIterable, Codable, Sendable {
    case tabs
    case spaces

    var displayName: String {
        switch self {
        case .tabs:
            return "Tabs"
        case .spaces:
            return "Spaces"
        }
    }

    static func current(userDefaults: UserDefaults = .standard) -> IndentationStyle {
        if let raw = userDefaults.string(forKey: AppConstants.Storage.indentationStyleKey),
           let style = IndentationStyle(rawValue: raw) {
            return style
        }
        return .tabs
    }

    static func setCurrent(_ style: IndentationStyle, userDefaults: UserDefaults = .standard) {
        userDefaults.set(style.rawValue, forKey: AppConstants.Storage.indentationStyleKey)
    }

    func indentUnit(tabWidth: Int = AppConstants.Editor.tabWidth) -> String {
        switch self {
        case .tabs:
            return "\t"
        case .spaces:
            return String(repeating: " ", count: tabWidth)
        }
    }
}

/// Application constants to replace magic numbers
enum AppConstants {

    // MARK: - Terminal Constants

    enum Terminal {
        static let defaultRows = 24
        static let defaultColumns = 150 // Increased to prevent premature wrapping
        static let charWidth: CGFloat = 7.2
        static let charHeight: CGFloat = 14.0
        static let responseDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
        static let terminalFontSize: CGFloat = 12
        static let terminalFontWeight: NSFont.Weight = .regular
    }

    // MARK: - Editor Constants

    enum Editor {
        static let defaultFontSize: Double = 12
        static let minFontSize: Double = 8
        static let maxFontSize: Double = 72
        static let lineNumberWidth: CGFloat = 45
        static let lineHeight: CGFloat = 15
        static let tabWidth: Int = 4
        static let defaultFontFamily: String = "SF Mono"
    }

    // MARK: - Layout Constants

    enum Layout {
        static let defaultSidebarWidth: Double = 250
        static let defaultTerminalHeight: Double = 200
        static let defaultChatPanelWidth: Double = 300
        static let minSidebarWidth: Double = 150
        static let maxSidebarWidth: Double = 500
        static let minTerminalHeight: Double = 100
        static let maxTerminalHeight: Double = 600
        static let minChatPanelWidth: Double = 200
        static let maxChatPanelWidth: Double = 600
        static let headerHeight: CGFloat = 30
    }

    // MARK: - File System Constants

    enum FileSystem {
        static let maxFileNameLength = 255
        static let maxPathLength = 4096
        static let maxRecentFiles = 10
        static let maxHistoryCount = 50
    }

    // MARK: - Time Constants

    enum Time {
        static let errorAutoDismissDelay: TimeInterval = 5.0
        static let searchDebounceDelay: TimeInterval = 0.25
        static let quickSearchDebounceNanoseconds: UInt64 = 150_000_000
        static let processTerminationTimeout: TimeInterval = 0.5
    }

    enum UI {
        static let internalTerminalPanelName: String = "Internal.Terminal"
    }

    enum Overlay {
        static let backdropOpacity: Double = 0.25
        static let containerPadding: CGFloat = 16
        static let containerCornerRadius: CGFloat = 12
        static let containerShadowRadius: CGFloat = 30
        static let hostPadding: CGFloat = 30

        static let listItemSpacing: CGFloat = 8
        static let listItemKindWidth: CGFloat = 80

        static let listMinWidth: CGFloat = 760
        static let listMinHeight: CGFloat = 420

        static let wideListMinWidth: CGFloat = 820
        static let wideListMinHeight: CGFloat = 460

        static let textFieldMinWidth: CGFloat = 520
        static let searchFieldMinWidth: CGFloat = 420
    }

    enum Settings {
        static let cardPadding: CGFloat = 16
        static let cardCornerRadius: CGFloat = 16

        static let sectionSpacing: CGFloat = 20

        static let pickerWideWidth: CGFloat = 220
        static let pickerNarrowWidth: CGFloat = 200
        static let sliderWidth: CGFloat = 180

        static let rowSpacing: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconFrameWidth: CGFloat = 24

        static let statusTextSize: CGFloat = 12

        static let contentTopPadding: CGFloat = 4
    }

    // MARK: - Color Constants

    enum Colors {
        static let terminalGreen = NSColor.green
        static let terminalBlack = NSColor.black
        static let terminalWhite = NSColor.white
        static let accentColor = Color.accentColor
        static let secondaryColor = Color.secondary
    }

    // MARK: - Validation Constants

    enum Validation {
        static let reservedFileNames = [
            "CON", "PRN", "AUX", "NUL",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
        ]
        static let invalidFileNameChars = CharacterSet(charactersIn: "<>:\"?*\\n\\r/\\\\")
    }

    // MARK: - AI Service Constants

    enum AI {
        static let defaultResponseDelay: UInt64 = 1_000_000_000
        static let minResponseDelay: UInt64 = 100_000_000 // 0.1 seconds
        static let maxResponseDelay: UInt64 = 10_000_000_000 // 10 seconds
    }

    // MARK: - Indexing Constants

    enum Indexing {
        static let allowedExtensions: Set<String> = [
            "swift", "js", "jsx", "ts", "tsx", "py", "html", "css", "json", "yaml", "yml", "md", "markdown"
        ]
        static let aiEnrichableExtensions: Set<String> = [
            "swift", "js", "jsx", "ts", "tsx", "py", "html", "css"
        ]
    }

    // MARK: - Storage Constants

    enum Storage {
        static let themeKey = "AppTheme"
        static let fontSizeKey = "FontSize"
        static let fontFamilyKey = "FontFamily"
        static let indentationStyleKey = "IndentationStyle"
        static let lastWorkspacePathKey = "LastWorkspacePath"
        static let showLineNumbersKey = "ShowLineNumbers"
        static let wordWrapKey = "WordWrap"
        static let minimapVisibleKey = "MinimapVisible"
        static let sidebarWidthKey = "SidebarWidth"
        static let terminalHeightKey = "TerminalHeight"
        static let chatPanelWidthKey = "ChatPanelWidth"
        static let cliTimeoutSecondsKey = "Agent.CliTimeoutSeconds"
        static let codebaseIndexEnabledKey = "CodebaseIndexEnabled"
        static let codebaseIndexAIEnrichmentEnabledKey = "CodebaseIndexAIEnrichmentEnabled"
        static let enabledLanguageModulesKey = "EnabledLanguageModules"
    }
}
